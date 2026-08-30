require "test_helper"

class AuthorizationCodeFlowTest < ActionDispatch::IntegrationTest
  setup do
    @actor = create_actor(email: "owner@probe.example.com", name: "Owner")
    @registration = register
    host! host_for(@tenant)
  end

  test "a code becomes an access token, an id token and a refresh token" do
    body = access_token_for(actor: @actor, registration: @registration)

    assert_equal "Bearer", body["token_type"]
    assert_operator body["expires_in"], :>, 0

    access = claims_in(body["access_token"])
    assert_equal origin_for(@tenant), access["iss"]
    assert_equal @actor.uuid, access["sub"]
    assert_equal @registration["client_id"], access["client_id"]
    assert_equal @tenant.uuid, access.dig("tenant", "uuid")

    id_token = claims_in(body["id_token"])
    assert_equal @registration["client_id"], id_token["aud"]
    assert_equal @actor.nickname, id_token["preferred_username"]

    assert body["refresh_token"].present?
  end

  test "an id token carries the nonce the authorization asked for" do
    sign_in_as(@actor)
    authorize(client_id: @registration["client_id"], nonce: "n-once")
    consent!

    body = token(
      grant_type: "authorization_code", code: code_from,
      redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier,
      client_id: @registration["client_id"], client_secret: @registration["client_secret"]
    )

    assert_equal "n-once", claims_in(body["id_token"])["nonce"]
  end

  test "the authorization response names the issuer that answered it" do
    sign_in_as(@actor)
    authorize(client_id: @registration["client_id"], state: "opaque")
    consent!

    assert_equal origin_for(@tenant), redirected["iss"]
    assert_equal "opaque", redirected["state"]
  end

  test "an unauthenticated authorize sends the caller to sign in" do
    authorize(client_id: @registration["client_id"])

    assert_redirected_to login_path
  end

  test "a code is single use" do
    code = authorized_code(actor: @actor, registration: @registration)

    exchange = lambda do
      token(
        grant_type: "authorization_code", code: code,
        redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier,
        client_id: @registration["client_id"], client_secret: @registration["client_secret"]
      )
    end

    assert exchange.call["access_token"].present?
    assert_equal "invalid_grant", exchange.call["error"]
  end

  test "a wrong code_verifier is refused and burns the code" do
    code = authorized_code(actor: @actor, registration: @registration)

    refused = token(
      grant_type: "authorization_code", code: code,
      redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: SecureRandom.urlsafe_base64(64),
      client_id: @registration["client_id"], client_secret: @registration["client_secret"]
    )

    assert_equal "invalid_grant", refused["error"]

    retried = token(
      grant_type: "authorization_code", code: code,
      redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier,
      client_id: @registration["client_id"], client_secret: @registration["client_secret"]
    )

    assert_equal "invalid_grant", retried["error"]
  end

  test "a code is bound to the redirect_uri it was issued for" do
    code = authorized_code(actor: @actor, registration: @registration)

    body = token(
      grant_type: "authorization_code", code: code,
      redirect_uri: "https://probe.example.com/elsewhere", code_verifier: verifier,
      client_id: @registration["client_id"], client_secret: @registration["client_secret"]
    )

    assert_equal "invalid_grant", body["error"]
    assert_match "redirect_uri", body["error_description"]
  end

  test "a code is bound to the client it was issued to" do
    other = register(client_name: "Other")
    code = authorized_code(actor: @actor, registration: @registration)

    body = token(
      grant_type: "authorization_code", code: code,
      redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier,
      client_id: other["client_id"], client_secret: other["client_secret"]
    )

    assert_equal "invalid_grant", body["error"]
  end

  test "a public client must send a code challenge" do
    public_client = register(token_endpoint_auth_method: "none")
    sign_in_as(@actor)

    authorize(
      client_id: public_client["client_id"],
      code_challenge: nil, code_challenge_method: nil
    )

    assert_equal "invalid_request", redirected["error"]
  end

  test "plain is not an accepted challenge method" do
    sign_in_as(@actor)
    authorize(client_id: @registration["client_id"], code_challenge_method: "plain")

    assert_equal "invalid_request", redirected["error"]
    assert_match "S256", redirected["error_description"]
  end

  test "an unregistered redirect_uri is refused without redirecting to it" do
    sign_in_as(@actor)
    authorize(client_id: @registration["client_id"], redirect_uri: "https://attacker.example.com/cb")

    assert_response :bad_request
    assert_equal "invalid_request", JSON.parse(response.body)["error"]
  end

  test "a scope the client does not hold is refused" do
    sign_in_as(@actor)
    authorize(client_id: @registration["client_id"], scope: "openid admin")

    assert_equal "invalid_scope", redirected["error"]
  end

  test "an unsupported response_type is refused" do
    sign_in_as(@actor)
    authorize(client_id: @registration["client_id"], response_type: "token")

    assert_equal "unsupported_response_type", redirected["error"]
  end

  test "an unsupported grant_type is refused" do
    assert_equal "unsupported_grant_type", token(grant_type: "password")["error"]
  end

  test "a wrong client secret fails client authentication" do
    code = authorized_code(actor: @actor, registration: @registration)

    body = token(
      grant_type: "authorization_code", code: code,
      redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier,
      client_id: @registration["client_id"], client_secret: "not-the-secret"
    )

    assert_response :unauthorized
    assert_equal "invalid_client", body["error"]
  end

  test "client_secret_basic authenticates as well as client_secret_post" do
    code = authorized_code(actor: @actor, registration: @registration)
    credentials = Base64.strict_encode64(
      "#{@registration['client_id']}:#{@registration['client_secret']}"
    )

    post "/token",
         params: URI.encode_www_form(
           grant_type: "authorization_code", code: code,
           redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier
         ),
         headers: {
           "CONTENT_TYPE" => "application/x-www-form-urlencoded",
           "HTTP_AUTHORIZATION" => "Basic #{credentials}"
         }

    assert_response :success
    assert JSON.parse(response.body)["access_token"].present?
  end
end
