require "test_helper"
require_relative "../support/dpop"

class DpopTest < ActionDispatch::IntegrationTest
  include DpopProofs

  setup do
    @actor = create_actor(email: "owner@example.com")
    host! host_for(@tenant)
    @registration = register(@tenant)
    @origin = origin_for(@tenant)
  end

  test "the server says which algorithms a proof may be signed with" do
    get "/.well-known/openid-configuration"

    held = JSON.parse(response.body)["dpop_signing_alg_values_supported"]

    assert_includes held, "ES256"
    assert_not_includes held, "none"
    assert_empty held.select { |alg| alg.start_with?("HS") }
  end

  test "a token asked for with a proof is held to the key that made it" do
    granted = bound_token

    assert_equal "DPoP", granted["token_type"]

    claims = claims_in(granted["access_token"])

    assert_equal dpop_jkt, claims.dig("cnf", "jkt")
  end

  test "a token asked for without a proof is a bearer token as before" do
    granted = access_token_for(actor: @actor, registration: @registration)

    assert_equal "Bearer", granted["token_type"]
    assert_nil claims_in(granted["access_token"])["cnf"]
  end

  test "a bound token opens a resource when the proof comes with it" do
    granted = bound_token

    get "/userinfo",
        headers: {
          "Authorization" => "DPoP #{granted['access_token']}"
        }.merge(
          with_dpop(method: :get, url: "#{@origin}/userinfo", access_token: granted["access_token"])
        )

    assert_response :success
    assert_equal @actor.uuid, JSON.parse(response.body)["sub"]
  end

  test "a bound token is refused when it is presented as a bearer token" do
    granted = bound_token

    get "/userinfo", headers: { "Authorization" => "Bearer #{granted['access_token']}" }

    assert_response :unauthorized
    assert_match(/bound to a key/, response.headers["WWW-Authenticate"].to_s)
  end

  test "a bound token is refused when another key made the proof" do
    granted = bound_token
    stranger = OpenSSL::PKey::EC.generate("prime256v1")

    get "/userinfo",
        headers: {
          "Authorization" => "DPoP #{granted['access_token']}"
        }.merge(
          with_dpop(
            method: :get, url: "#{@origin}/userinfo",
            key: stranger, access_token: granted["access_token"]
          )
        )

    assert_response :unauthorized
    assert_match(/another key/, response.headers["WWW-Authenticate"].to_s)
  end

  test "a proof that does not name the token it came with is refused" do
    granted = bound_token

    get "/userinfo",
        headers: {
          "Authorization" => "DPoP #{granted['access_token']}"
        }.merge(with_dpop(method: :get, url: "#{@origin}/userinfo"))

    assert_response :unauthorized
    assert_match(/invalid_dpop_proof/, response.headers["WWW-Authenticate"].to_s)
  end

  test "a proof made for another URL is refused" do
    granted = bound_token

    get "/userinfo",
        headers: {
          "Authorization" => "DPoP #{granted['access_token']}"
        }.merge(
          with_dpop(
            method: :get, url: "#{@origin}/manage",
            access_token: granted["access_token"]
          )
        )

    assert_response :unauthorized
    assert_match(/another URL/, response.headers["WWW-Authenticate"].to_s)
  end

  test "a proof made for another method is refused" do
    granted = bound_token

    get "/userinfo",
        headers: {
          "Authorization" => "DPoP #{granted['access_token']}"
        }.merge(
          with_dpop(
            method: :post, url: "#{@origin}/userinfo",
            access_token: granted["access_token"]
          )
        )

    assert_response :unauthorized
    assert_match(/another method/, response.headers["WWW-Authenticate"].to_s)
  end

  test "a proof is good for one request and no more" do
    granted = bound_token
    held = with_dpop(method: :get, url: "#{@origin}/userinfo", access_token: granted["access_token"])
    headers = { "Authorization" => "DPoP #{granted['access_token']}" }.merge(held)

    get "/userinfo", headers: headers

    assert_response :success

    get "/userinfo", headers: headers

    assert_response :unauthorized
    assert_match(/already been used/, response.headers["WWW-Authenticate"].to_s)
  end

  test "a proof made too long ago is refused" do
    granted = bound_token

    get "/userinfo",
        headers: {
          "Authorization" => "DPoP #{granted['access_token']}"
        }.merge(
          with_dpop(
            method: :get, url: "#{@origin}/userinfo",
            access_token: granted["access_token"],
            iat: 10.minutes.ago.to_i
          )
        )

    assert_response :unauthorized
    assert_match(/too long ago/, response.headers["WWW-Authenticate"].to_s)
  end

  test "a proof carrying a private key is refused" do
    code = authorized_code(actor: @actor, registration: @registration)
    private_jwk = JWT::JWK.new(dpop_key).export(include_private: true)

    held = JWT.encode(
      { "jti" => SecureRandom.uuid, "htm" => "POST", "htu" => "#{@origin}/token", "iat" => Time.current.to_i },
      dpop_key, "ES256",
      { "typ" => Proof::TYPE, "jwk" => private_jwk }
    )

    answer = redeem(code, "HTTP_DPOP" => held)

    assert_equal "invalid_dpop_proof", answer["error"]
    assert_match(/must be public/, answer["error_description"])
  end

  test "a proof signed with a shared secret is refused" do
    code = authorized_code(actor: @actor, registration: @registration)

    held = JWT.encode(
      { "jti" => SecureRandom.uuid, "htm" => "POST", "htu" => "#{@origin}/token", "iat" => Time.current.to_i },
      "a shared secret", "HS256",
      { "typ" => Proof::TYPE, "jwk" => { "kty" => "oct", "k" => "YSBzaGFyZWQgc2VjcmV0" } }
    )

    answer = redeem(code, "HTTP_DPOP" => held)

    assert_equal "invalid_dpop_proof", answer["error"]
  end

  test "an unsigned proof is refused" do
    code = authorized_code(actor: @actor, registration: @registration)

    held = JWT.encode(
      { "jti" => SecureRandom.uuid, "htm" => "POST", "htu" => "#{@origin}/token", "iat" => Time.current.to_i },
      nil, "none",
      { "typ" => Proof::TYPE, "jwk" => dpop_jwk }
    )

    answer = redeem(code, "HTTP_DPOP" => held)

    assert_equal "invalid_dpop_proof", answer["error"]
  end

  test "a proof typed as something other than a proof is refused" do
    code = authorized_code(actor: @actor, registration: @registration)

    held = JWT.encode(
      { "jti" => SecureRandom.uuid, "htm" => "POST", "htu" => "#{@origin}/token", "iat" => Time.current.to_i },
      dpop_key, "ES256",
      { "typ" => "JWT", "jwk" => dpop_jwk }
    )

    answer = redeem(code, "HTTP_DPOP" => held)

    assert_equal "invalid_dpop_proof", answer["error"]
    assert_match(/typed/, answer["error_description"])
  end

  test "two proofs on one request are refused" do
    code = authorized_code(actor: @actor, registration: @registration)
    one = dpop_proof(method: :post, url: "#{@origin}/token")
    two = dpop_proof(method: :post, url: "#{@origin}/token")

    answer = redeem(code, "HTTP_DPOP" => "#{one},#{two}")

    assert_equal "invalid_dpop_proof", answer["error"]
    assert_match(/exactly one/, answer["error_description"])
  end

  test "a refresh token issued to a bound grant stays bound to the same key" do
    granted = bound_token
    stranger = OpenSSL::PKey::EC.generate("prime256v1")

    refused = refresh(granted["refresh_token"], key: stranger)

    assert_equal "invalid_dpop_proof", refused["error"]

    held = refresh(granted["refresh_token"])

    assert_equal "DPoP", held["token_type"]
    assert_equal dpop_jkt, claims_in(held["access_token"]).dig("cnf", "jkt")
  end

  test "a refresh token issued to a bound grant is refused with no proof at all" do
    granted = bound_token

    answer = token(
      grant_type: "refresh_token",
      refresh_token: granted["refresh_token"],
      client_id: @registration["client_id"],
      client_secret: @registration["client_secret"]
    )

    assert_equal "invalid_dpop_proof", answer["error"]
  end

  test "a code bound at the authorize endpoint may only be redeemed with that key" do
    sign_in_as(@actor)
    authorize(client_id: @registration["client_id"], dpop_jkt: dpop_jkt)
    consent! if awaiting_consent?

    code = code_from
    stranger = OpenSSL::PKey::EC.generate("prime256v1")

    refused = redeem(code, with_dpop(method: :post, url: "#{@origin}/token", key: stranger))

    assert_equal "invalid_dpop_proof", refused["error"]
    assert_match(/held to a key/, refused["error_description"])
  end

  test "a client that binds its tokens is refused a token with no proof" do
    held = register(@tenant, dpop_bound_access_tokens: true)

    assert_equal true, held["dpop_bound_access_tokens"]

    code = authorized_code(actor: @actor, registration: held)

    answer = token(
      grant_type: "authorization_code",
      code: code,
      redirect_uri: OidcFlow::REDIRECT_URI,
      code_verifier: verifier,
      client_id: held["client_id"],
      client_secret: held["client_secret"]
    )

    assert_equal "invalid_dpop_proof", answer["error"]
  end

  test "introspection says a token is held to a key" do
    granted = bound_token

    post "/introspect",
         params: { token: granted["access_token"] },
         headers: {
           "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
             @registration["client_id"], @registration["client_secret"]
           )
         }

    held = JSON.parse(response.body)

    assert_equal "DPoP", held["token_type"]
    assert_equal dpop_jkt, held.dig("cnf", "jkt")
  end

  test "the manage API takes a bound token" do
    within { @actor.grant!([ Scopes::MANAGE ]) }

    @registration = { "client_id" => manager.client_id, "client_secret" => nil }

    granted = bound_token(scope: "openid #{Scopes::MANAGE}", resource: "#{@origin}/manage")

    post "/manage/graphql",
         params: { query: "{ viewer { nickname } }" }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "Authorization" => "DPoP #{granted['access_token']}"
         }.merge(
           with_dpop(method: :post, url: "#{@origin}/manage/graphql", access_token: granted["access_token"])
         )

    assert_response :success
    assert_equal @actor.nickname, JSON.parse(response.body).dig("data", "viewer", "nickname")
  end

  private

    def manager
      @manager ||= create_client(
        @tenant,
        allowed_scopes: "openid profile email #{Scopes::MANAGE}",
        approved_at: Time.current,
        grant_types: [ "authorization_code", "refresh_token" ]
      )
    end

    def bound_token(scope: "openid profile email offline_access", resource: nil)
      code = authorized_code(actor: @actor, registration: @registration, scope: scope, resource: resource)

      redeem(code, with_dpop(method: :post, url: "#{@origin}/token"))
    end

    def redeem(code, headers)
      post "/token",
           params: URI.encode_www_form(
             grant_type: "authorization_code",
             code: code,
             redirect_uri: OidcFlow::REDIRECT_URI,
             code_verifier: verifier,
             client_id: @registration["client_id"],
             client_secret: @registration["client_secret"]
           ),
           headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }.merge(headers)

      JSON.parse(response.body)
    end

    def refresh(secret, key: dpop_key)
      post "/token",
           params: URI.encode_www_form(
             grant_type: "refresh_token",
             refresh_token: secret,
             client_id: @registration["client_id"],
             client_secret: @registration["client_secret"]
           ),
           headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }.merge(
             with_dpop(method: :post, url: "#{@origin}/token", key: key)
           )

      JSON.parse(response.body)
    end
end
