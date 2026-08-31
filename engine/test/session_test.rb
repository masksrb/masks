require "test_helper"

class SessionTest < EngineIntegrationTest
  test "an unconnected app refuses differently from a signed-out one" do
    get "/auth/session", headers: host.merge("HTTP_ACCEPT" => "application/json")

    assert_response :unauthorized
    assert_equal false, json["signed_in"]
    assert_equal "handshake_required", json["error"]
    assert_equal "/auth/handshake", json["handshake_url"]
  end

  test "a connected app that nobody has signed in to says login_required" do
    connect!

    get "/auth/session", headers: host.merge("HTTP_ACCEPT" => "application/json")

    assert_response :unauthorized
    assert_equal "login_required", json["error"]
    assert_equal "/auth/", json["login_url"]
  end

  test "a refusal is never cacheable" do
    connect!

    get "/auth/session", headers: host.merge("HTTP_ACCEPT" => "application/json")

    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "an unconnected app will not start a sign-in it cannot finish" do
    get "/auth", headers: host

    assert_redirected_to "/auth/handshake"
  end

  test "starting sends the browser to authorize with pkce, state and nonce" do
    connect!

    get "/auth", headers: host

    assert_response :redirect

    query = URI.decode_www_form(URI.parse(response.location).query).to_h

    assert response.location.start_with?("#{issuer.url_for(SUBDOMAIN)}/authorize")
    assert_equal "code", query["response_type"]
    assert_equal "test-client", query["client_id"]
    assert_equal "#{origin}/auth/callback", query["redirect_uri"]
    assert_equal "S256", query["code_challenge_method"]
    refute_empty query["code_challenge"]
    refute_empty query["state"]
    refute_empty query["nonce"]
    assert_includes query["scope"].split(" "), "openid"
  end

  test "the resource indicator travels with the authorization" do
    connect!

    get "/auth", headers: host

    query = URI.decode_www_form(URI.parse(response.location).query).to_h

    assert_equal "#{origin}/mcp", query["resource"]
  end

  test "a completed callback establishes a session that says who signed in" do
    sign_in!

    assert_redirected_to "/"

    get "/auth/session", headers: host.merge("HTTP_ACCEPT" => "application/json")

    assert_response :success
    assert_equal true, json["signed_in"]
    assert_equal "actor-1", json["subject"]
    assert_equal "owner@example.invalid", json["email"]
    assert_equal SUBDOMAIN, json.dig("tenant", "subdomain")
    assert_includes json["scopes"], "catalog:read"
  end

  test "the id token is not kept in the session" do
    sign_in!

    held = session_payload

    refute_includes held.keys, "id_token"
    assert_includes held.keys, "access_token"
    assert_includes held.keys, "identity"
  end

  test "the session fits a cookie store, which has a hard ceiling and no warning before it" do
    sign_in!

    value = response.headers["Set-Cookie"].to_s[/_masks_rails_test=([^;]+)/, 1].to_s

    refute_empty value
    assert value.bytesize < 4096, "the session cookie is #{value.bytesize} bytes of 4096"
  end

  test "a forged state is refused and nothing is established" do
    connect!

    get "/auth", headers: host
    landed = issuer.authorize!(response.location)

    get "/auth/callback?code=#{landed[:code]}&state=forged", headers: host

    assert_response :bad_request
    assert_empty session_payload
  end

  test "an id token carrying no nonce is refused rather than accepted vacuously" do
    issuer.id_tokens = :without_nonce

    sign_in!

    assert_response :bad_request
    assert_empty session_payload
  end

  test "an id token carrying another request's nonce is refused" do
    issuer.id_tokens = :foreign_nonce

    sign_in!

    assert_response :bad_request
    assert_empty session_payload
  end

  test "a token response with no id token at all is refused when one was asked for" do
    issuer.id_tokens = :absent

    sign_in!

    assert_response :bad_request
    assert_empty session_payload
  end

  test "a callback with nothing in flight is refused" do
    connect!

    get "/auth/callback?code=whatever&state=whatever", headers: host

    assert_response :bad_request
  end

  test "a code the issuer never issued is refused" do
    connect!

    get "/auth", headers: host
    landed = issuer.authorize!(response.location)

    get "/auth/callback?code=never-issued&state=#{landed[:state]}", headers: host

    assert_response :bad_request
    assert_empty session_payload
  end

  test "a code cannot be redeemed twice" do
    connect!

    get "/auth", headers: host
    landed = issuer.authorize!(response.location)

    get "/auth/callback?code=#{landed[:code]}&state=#{landed[:state]}", headers: host
    assert_response :redirect

    get "/auth", headers: host
    again = issuer.authorize!(response.location)

    get "/auth/callback?code=#{landed[:code]}&state=#{again[:state]}", headers: host
    assert_response :bad_request
  end

  test "an error from the issuer is refused rather than exchanged" do
    connect!

    get "/auth", headers: host

    get "/auth/callback?error=access_denied&error_description=declined", headers: host

    assert_response :bad_request
    assert_empty session_payload
  end

  test "where you were headed survives the round trip" do
    connect!

    get "/dashboard", headers: host
    assert_redirected_to "/auth/"

    get "/auth", headers: host
    landed = issuer.authorize!(response.location)

    get "/auth/callback?code=#{landed[:code]}&state=#{landed[:state]}", headers: host

    assert_redirected_to "/dashboard"
  end

  test "return_to is refused when it points off this host" do
    connect!

    get "/auth?return_to=#{CGI.escape('https://elsewhere.test/steal')}", headers: host
    landed = issuer.authorize!(response.location)

    get "/auth/callback?code=#{landed[:code]}&state=#{landed[:state]}", headers: host

    assert_redirected_to "/"
  end

  test "a protocol-relative return_to is refused too" do
    connect!

    get "/auth?return_to=#{CGI.escape('//elsewhere.test/steal')}", headers: host
    landed = issuer.authorize!(response.location)

    get "/auth/callback?code=#{landed[:code]}&state=#{landed[:state]}", headers: host

    assert_redirected_to "/"
  end

  test "a signed-in browser reaches a page that requires signing in" do
    sign_in!

    get "/dashboard", headers: host

    assert_response :success
    assert_includes response.body, "actor-1"
  end

  test "signing out drops the session" do
    sign_in!

    post "/auth/logout", headers: host

    assert_redirected_to "/"
    assert_empty session_payload

    get "/auth/session", headers: host.merge("HTTP_ACCEPT" => "application/json")

    assert_response :unauthorized
  end

  test "signing out drops the local session and leaves the issuer's" do
    sign_in!

    delete "/auth/logout", headers: host.merge("HTTP_ACCEPT" => "application/json")

    assert_response :success
    assert_equal false, json["signed_in"]
    assert_nil json["logout_url"], "nothing asked to sign out of masks"
    assert_empty session_payload
  end

  test "signing out everywhere hands back where to end the issuer's session" do
    sign_in!

    delete "/auth/logout?everywhere=1", headers: host.merge("HTTP_ACCEPT" => "application/json")

    assert_response :success
    assert_equal false, json["signed_in"]

    query = URI.decode_www_form(URI.parse(json["logout_url"]).query).to_h

    assert json["logout_url"].start_with?("#{issuer.url_for(SUBDOMAIN)}/logout")
    assert_equal "test-client", query["client_id"]
    assert_equal "#{origin}/", query["post_logout_redirect_uri"]
    refute_empty query["state"]
  end

  test "a consumer can make signing out mean signing out of masks" do
    Masks::Rails.config.sign_out_of_issuer = true

    sign_in!

    delete "/auth/logout", headers: host

    assert_response :redirect
    assert response.location.start_with?("#{issuer.url_for(SUBDOMAIN)}/logout")
    assert_empty session_payload
  ensure
    Masks::Rails.config.sign_out_of_issuer = false
  end

  test "an unconnected app offers no logout url, rather than a broken one" do
    delete "/auth/logout?everywhere=1", headers: host.merge("HTTP_ACCEPT" => "application/json")

    assert_response :success
    assert_nil json["logout_url"]
  end

  private

    def session_payload
      request.session["masks"] || {}
    end
end
