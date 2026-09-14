require "test_helper"

class RequestObjectTest < ActionDispatch::IntegrationTest
  setup do
    host! host_for(@tenant)
    @actor = create_actor(email: "owner@probe.example.com", name: "Owner")
    @key = OpenSSL::PKey::EC.generate("prime256v1")
    @registration = register(jwks: jwks)
    @client_id = @registration["client_id"]
  end

  def jwks(key = @key)
    { "keys" => [ JWT::JWK.new(key, kid: "k-1").export.transform_keys(&:to_s) ] }
  end

  def signed(key: @key, typ: RequestObject::TYPE, alg: "ES256", **claims)
    now = Time.current.to_i

    JWT.encode({
      "iss" => @client_id, "aud" => origin_for(@tenant), "client_id" => @client_id,
      "iat" => now, "nbf" => now, "exp" => now + 300, "jti" => SecureRandom.uuid,
      "response_type" => "code", "redirect_uri" => OidcFlow::REDIRECT_URI,
      "scope" => "openid profile", "state" => "signed-state", "nonce" => "signed-nonce",
      "code_challenge" => challenge, "code_challenge_method" => "S256"
    }.merge(claims.transform_keys(&:to_s)).compact, key, alg, { kid: "k-1", typ: typ })
  end

  def visit(**params)
    get "/authorize?#{URI.encode_www_form({ client_id: @client_id }.merge(params))}"
  end

  def client
    within { Client.find_by!(client_id: @client_id) }
  end

  test "discovery says request objects are read and which algorithms sign them" do
    get "/.well-known/openid-configuration"
    config = JSON.parse(response.body)

    assert config["request_parameter_supported"]
    assert_includes config["request_object_signing_alg_values_supported"], "ES256"
    refute config["request_uri_parameter_supported"]
  end

  test "a signed request object is the whole request, and the query beside it is ignored" do
    sign_in_as(@actor)
    visit(request: signed, state: "forged", scope: "openid profile email", redirect_uri: "https://evil.example/cb")
    consent! if awaiting_consent?

    assert response.location.start_with?(OidcFlow::REDIRECT_URI)
    assert_equal "signed-state", redirected["state"]

    body = token(grant_type: "authorization_code", code: code_from, redirect_uri: OidcFlow::REDIRECT_URI,
                 code_verifier: verifier, client_id: @client_id, client_secret: @registration["client_secret"])

    assert_equal "openid profile", body["scope"]
    assert_equal "signed-nonce", claims_in(body["id_token"])["nonce"]
  end

  test "a request object signed by another key is refused" do
    visit(request: signed(key: OpenSSL::PKey::EC.generate("prime256v1")))

    assert_equal "invalid_request_object", error_from_response
  end

  test "a request object addressed to another issuer is refused" do
    visit(request: signed(aud: "https://elsewhere.example"))

    assert_equal "invalid_request_object", error_from_response
  end

  test "a request object naming another client inside is refused" do
    visit(request: signed(client_id: "someone-else"))

    assert_equal "invalid_request_object", error_from_response
  end

  test "an expired request object is refused" do
    visit(request: signed(exp: 10.minutes.ago.to_i))

    assert_equal "invalid_request_object", error_from_response
  end

  test "a request object without an expiry is refused" do
    visit(request: signed(exp: nil))

    assert_equal "invalid_request_object", error_from_response
  end

  test "a request object typed as something else is refused" do
    visit(request: signed(typ: "at+jwt"))

    assert_equal "invalid_request_object", error_from_response
  end

  test "a request object is used once" do
    object = signed
    sign_in_as(@actor)

    visit(request: object)
    consent! if awaiting_consent?
    assert redirected["code"].present?

    visit(request: object)
    assert_equal "invalid_request_object", error_from_response
  end

  test "both a request and a request_uri at once are refused" do
    visit(request: signed, request_uri: "#{PushedRequest::PREFIX}anything")

    assert_equal "invalid_request", error_from_response
  end

  test "a signed request object can be pushed, and the client_id comes from authentication" do
    post "/par", params: { client_id: @client_id, client_secret: @registration["client_secret"], request: signed }

    assert_response :created
    request_uri = JSON.parse(response.body)["request_uri"]

    sign_in_as(@actor)
    visit(request_uri: request_uri)
    consent! if awaiting_consent?

    assert_equal "signed-state", redirected["state"]
  end

  test "a pushed request object that does not verify is refused at the push" do
    post "/par", params: { client_id: @client_id, client_secret: @registration["client_secret"],
                           request: signed(key: OpenSSL::PKey::EC.generate("prime256v1")) }

    assert_response :bad_request
    assert_equal "invalid_request_object", JSON.parse(response.body)["error"]
  end

  test "a client that requires signed requests refuses a plain one at authorize and at the push" do
    within { client.update!(require_signed_request_object: true) }

    sign_in_as(@actor)
    authorize(client_id: @client_id)
    assert_equal "invalid_request", error_from_response

    post "/par", params: { client_id: @client_id, client_secret: @registration["client_secret"],
                           response_type: "code", redirect_uri: OidcFlow::REDIRECT_URI, scope: "openid",
                           code_challenge: challenge, code_challenge_method: "S256" }
    assert_response :bad_request

    visit(request: signed)
    consent! if awaiting_consent?
    assert redirected["code"].present?
  end

  test "a client registers the requirement, and cannot without keys to check it against" do
    assert register(jwks: jwks, require_signed_request_object: true)["require_signed_request_object"]
    assert_equal "invalid_client_metadata", register(require_signed_request_object: true)["error"]
  end

  private

    def error_from_response
      return redirected["error"] if response.redirect?

      response.body[/invalid_request_object|invalid_request/]
    end
end
