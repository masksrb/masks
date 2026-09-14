require "test_helper"

class PrivateKeyJwtTest < ActionDispatch::IntegrationTest
  ASSERTION = ClientAssertion::TYPE
  JWKS_URI = "https://indexer.example.com/jwks.json".freeze

  setup do
    host! host_for(@tenant)
    @key = OpenSSL::PKey::RSA.generate(2048)
    @kid = SecureRandom.uuid
    @service = service
  end

  def public_jwks(key = @key, kid: @kid)
    { "keys" => [ JWT::JWK.new(key.public_key, kid: kid).export.transform_keys(&:to_s) ] }
  end

  def service(**attributes)
    within do
      Client.create!(
        client_id: SecureRandom.uuid, name: "Indexer",
        grant_types: [ Client::CLIENT_CREDENTIALS ], response_types: [],
        resources: [ "https://uris.example.com/mcp" ], allowed_scopes: "uris:catalog:read",
        token_endpoint_auth_method: Client::PRIVATE_KEY_JWT, jwks: public_jwks,
        approved_at: Time.current, **attributes
      )
    end
  end

  def assertion(client = @service, key: @key, kid: @kid, alg: "RS256", aud: origin_for(@tenant), **claims)
    now = Time.current.to_i

    JWT.encode({
      "iss" => client.client_id, "sub" => client.client_id, "aud" => aud,
      "iat" => now, "exp" => now + 60, "jti" => SecureRandom.uuid
    }.merge(claims.transform_keys(&:to_s)).compact, key, alg, { kid: kid })
  end

  def grant(signed = assertion, **params)
    token(grant_type: Client::CLIENT_CREDENTIALS, client_assertion_type: ASSERTION, client_assertion: signed, **params)
  end

  test "a client signs in with an assertion made with its own key" do
    body = grant

    assert_equal "uris:catalog:read", body["scope"], body
    assert_equal @service.client_id, claims_in(body["access_token"])["sub"]
  end

  test "the token endpoint itself is an audience an assertion may name" do
    assert grant(assertion(aud: "#{origin_for(@tenant)}/token"))["access_token"]
  end

  test "an assertion is spent the first time it is used" do
    signed = assertion

    assert grant(signed)["access_token"]
    assert_equal "invalid_client", grant(signed)["error"]
  end

  test "an assertion signed by another key is refused" do
    body = grant(assertion(key: OpenSSL::PKey::RSA.generate(2048)))

    assert_equal "invalid_client", body["error"]
    assert_response :unauthorized
  end

  test "an assertion for another audience is refused" do
    assert_equal "invalid_client", grant(assertion(aud: "https://elsewhere.example.com"))["error"]
  end

  test "an assertion that does not name the client as its own issuer is refused" do
    assert_equal "invalid_client", grant(assertion(iss: "somebody"))["error"]
  end

  test "an expired assertion is refused" do
    assert_equal "invalid_client", grant(assertion(exp: 5.minutes.ago.to_i))["error"]
  end

  test "an assertion that would live for a day is refused" do
    assert_equal "invalid_client", grant(assertion(exp: 1.day.from_now.to_i))["error"]
  end

  test "an assertion without a jti is refused" do
    assert_equal "invalid_client", grant(assertion(jti: nil))["error"]
  end

  test "an assertion signed with a shared secret is refused" do
    body = grant(assertion(key: "a-secret-anybody-could-guess", alg: "HS256"))

    assert_equal "invalid_client", body["error"]
  end

  test "an unsigned assertion is refused" do
    now = Time.current.to_i
    unsigned = JWT.encode({ "iss" => @service.client_id, "sub" => @service.client_id, "aud" => origin_for(@tenant),
                            "exp" => now + 60, "jti" => SecureRandom.uuid }, nil, "none")

    assert_equal "invalid_client", grant(unsigned)["error"]
  end

  test "a client that signs assertions cannot fall back to a secret" do
    body = token(grant_type: Client::CLIENT_CREDENTIALS, client_id: @service.client_id, client_secret: "anything")

    assert_equal "invalid_client", body["error"]
  end

  test "a client with a secret cannot present an assertion instead" do
    secretive = within do
      Client.new(client_id: SecureRandom.uuid, name: "Secretive", grant_types: [ Client::CLIENT_CREDENTIALS ],
                 allowed_scopes: "uris:catalog:read", approved_at: Time.current).tap(&:issue_credentials!)
    end

    assert_equal "invalid_client", grant(assertion(secretive))["error"]
  end

  test "keys are read from a jwks_uri and read again when a new kid turns up" do
    rotated = OpenSSL::PKey::RSA.generate(2048)

    stub_request(:get, JWKS_URI)
      .to_return({ status: 200, body: public_jwks.to_json }, { status: 200, body: public_jwks.to_json },
                 { status: 200, body: public_jwks(rotated, kid: "next").to_json })

    remote = service(jwks: nil, jwks_uri: JWKS_URI)

    assert grant(assertion(remote))["access_token"]
    assert grant(assertion(remote, key: rotated, kid: "next"))["access_token"]
    assert_requested :get, JWKS_URI, times: 3
  end

  test "introspection accepts an assertion made out to its own endpoint" do
    access = grant["access_token"]

    post "/introspect", params: {
      token: access, client_assertion_type: ASSERTION,
      client_assertion: assertion(aud: "#{origin_for(@tenant)}/introspect")
    }

    assert JSON.parse(response.body)["active"]
  end

  test "a client registers its keys and is issued no secret" do
    body = register(token_endpoint_auth_method: Client::PRIVATE_KEY_JWT, jwks: public_jwks)

    assert body["client_id"], body
    assert_nil body["client_secret"]
    assert_equal public_jwks, body["jwks"]
  end

  test "registering for private_key_jwt without any keys is refused" do
    assert_equal "invalid_client_metadata", register(token_endpoint_auth_method: Client::PRIVATE_KEY_JWT)["error"]
  end

  test "registering a private key is refused" do
    body = register(token_endpoint_auth_method: Client::PRIVATE_KEY_JWT,
                    jwks: { "keys" => [ JWT::JWK.new(@key).export(include_private: true) ] })

    assert_equal "invalid_client_metadata", body["error"]
    assert_match "public", body["error_description"]
  end

  test "a registered client signs in with an assertion at the end of the code flow" do
    registered = register(token_endpoint_auth_method: Client::PRIVATE_KEY_JWT, jwks: public_jwks)
    client = within { Client.find_by!(client_id: registered["client_id"]) }
    actor = create_actor

    code = authorized_code(actor: actor, registration: registered)

    body = token(grant_type: "authorization_code", code: code, redirect_uri: OidcFlow::REDIRECT_URI,
                 code_verifier: verifier, client_assertion_type: ASSERTION, client_assertion: assertion(client))

    assert body["access_token"], body
    assert body["id_token"]
  end

  test "discovery offers private_key_jwt and the algorithms it checks" do
    get "/.well-known/openid-configuration"
    config = JSON.parse(response.body)

    assert_includes config["token_endpoint_auth_methods_supported"], Client::PRIVATE_KEY_JWT
    assert_includes config["token_endpoint_auth_signing_alg_values_supported"], "ES256"
    refute_includes config["token_endpoint_auth_signing_alg_values_supported"], "HS256"
  end
end
