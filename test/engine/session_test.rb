require_relative "test_helper"

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

  ADMIN = { admin: %w[catalog:admin], owner: { role: "owner" }, read: %w[catalog:read] }.freeze

  def privileged!(granted)
    get "/settings", headers: host
    assert_redirected_to %r{/auth/\?return_to=%2Fsettings&privilege=admin}

    get URI.parse(response.location).request_uri, headers: host
    assert_includes URI.decode_www_form(URI.parse(response.location).query).to_h["scope"].split(" "), "catalog:admin"

    landed = issuer.authorize!(response.location, scopes: granted)
    get "/auth/callback?code=#{landed[:code]}&state=#{landed[:state]}", headers: host
    assert_redirected_to "/settings"

    get "/settings", headers: host
  end

  test "a page that needs a privilege sends someone who holds it through masks once and back" do
    configure!(privileges: ADMIN)
    sign_in!

    privileged!(%w[openid profile email catalog:read catalog:admin])

    assert_response :ok
    assert_equal "settings", response.body
  end

  test "someone masks will not grant the privilege is refused after one try, not sent around again" do
    configure!(privileges: ADMIN)
    sign_in!

    privileged!(%w[openid profile email catalog:read])

    assert_response :forbidden
    assert_match "admin privilege", response.body
  end

  test "a JSON request that needs a privilege is told where to sign in" do
    configure!(privileges: ADMIN)
    sign_in!

    get "/settings", headers: host.merge("HTTP_ACCEPT" => "application/json")

    assert_response :forbidden
    assert_equal "privilege_required", json["error"]
    assert_equal %w[admin], json["privileges"]
    assert_match "privilege=admin", json["login_url"]
  end

  test "the session says which privileges the sign-in holds" do
    configure!(privileges: ADMIN)
    sign_in!

    get "/auth/session", headers: host

    assert_equal %w[read], json["privileges"]
  end

  test "a privilege the app never defined is a mistake in the app" do
    configure!(privileges: {})

    assert_raises(ArgumentError) { Masks::Rails.config.privilege(:admin) }
  end

  test "a privilege is a list of scopes, or names scopes, roles, and an organization" do
    configure!(privileges: { admin: %w[catalog:admin], billing: { role: %w[owner billing], organization: "acme" } })

    assert_equal %w[catalog:admin], Masks::Rails.config.privilege(:admin).scopes
    assert_equal %w[owner billing], Masks::Rails.config.privilege(:billing).roles
    assert_equal "acme", Masks::Rails.config.privilege(:billing).organization
    assert_raises(ArgumentError) { configure!(privileges: { admin: { scopes: %w[catalog:admin] } }) }
  end

  test "a sign-in asks for a privilege's scopes on top of the usual scope" do
    configure!(privileges: ADMIN)
    connect!

    get "/auth?privilege=admin", headers: host

    scopes = URI.decode_www_form(URI.parse(response.location).query).to_h["scope"].split(" ")

    assert_includes scopes, "catalog:admin"
    assert_includes scopes, "catalog:read"
  end

  test "the handshake registers every privilege's scopes, so the issuer lets the app ask for them" do
    configure!(privileges: ADMIN)

    assert_includes Masks::Rails.config.approved_scope, "catalog:admin"
  end

  test "a sign-in asks for nothing beyond the usual scope for a privilege the app does not define" do
    configure!(privileges: ADMIN)
    connect!

    get "/auth?privilege=root", headers: host

    scopes = URI.decode_www_form(URI.parse(response.location).query).to_h["scope"].split(" ")

    assert_equal %w[openid profile email offline_access catalog:read], scopes
  end

  test "an issuer that has forgotten the client asks for a reconnect rather than an authorize it will refuse" do
    shake_hands!

    issuer.forgotten = true

    get "/auth", headers: host

    assert_redirected_to "/auth/handshake"
    assert_nil CREDENTIALS[HOST],
               "a client_id the issuer does not know is worth nothing but a dead end"

    get "/auth/session", headers: host.merge("HTTP_ACCEPT" => "application/json")

    assert_response :unauthorized
    assert_equal "handshake_required", json["error"]
  end

  test "an issuer that does not answer a registration read is not taken to have forgotten anything" do
    shake_hands!

    CREDENTIALS.hold!(
      HOST,
      **CREDENTIALS[HOST],
      registration_client_uri: "#{issuer.url_for(SUBDOMAIN)}/register"
    )

    get "/auth", headers: host

    assert_response :redirect
    assert response.location.start_with?("#{issuer.url_for(SUBDOMAIN)}/authorize"),
           "404 means the issuer does not answer RFC 7592 reads, not that the client is gone"
    refute_nil CREDENTIALS[HOST]
  end

  test "an app whose store cannot forget keeps the sign-in it has always had" do
    configure!(forget: nil)

    CREDENTIALS.hold!(
      HOST,
      client_id: "test-client",
      client_secret: "test-secret",
      registration_access_token: "held",
      registration_client_uri: "#{issuer.url_for(SUBDOMAIN)}/register/test-client"
    )

    issuer.forgotten = true

    get "/auth", headers: host

    assert_response :redirect
    assert response.location.start_with?("#{issuer.url_for(SUBDOMAIN)}/authorize")
  end

  test "a refresh the issuer refuses as an unknown client asks for a reconnect, not another sign-in" do
    shake_hands!

    get "/auth", headers: host
    landed = issuer.authorize!(response.location)

    get "/auth/callback?code=#{landed[:code]}&state=#{landed[:state]}", headers: host

    assert_redirected_to "/"

    issuer.forgotten = true

    travel 2.hours do
      get "/auth/session", headers: host.merge("HTTP_ACCEPT" => "application/json")
    end

    assert_response :unauthorized
    assert_equal "handshake_required", json["error"]
    assert_nil CREDENTIALS[HOST]
    assert_empty session_payload
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
    assert_equal "#{issuer.url_for(SUBDOMAIN)}/", json["account_url"], "where the person manages their account in masks"
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

  test "two sign-ins started in two tabs both complete, in either order" do
    connect!

    get "/auth?return_to=/first", headers: host
    first = issuer.authorize!(response.location)

    get "/auth?return_to=/second", headers: host
    second = issuer.authorize!(response.location)

    refute_equal first[:state], second[:state]

    get "/auth/callback?code=#{second[:code]}&state=#{second[:state]}", headers: host
    assert_redirected_to "/second"

    get "/auth/callback?code=#{first[:code]}&state=#{first[:state]}", headers: host
    assert_redirected_to "/first"
  end

  test "a second tab starting does not sign the browser out of the first" do
    sign_in!

    get "/auth", headers: host
    issuer.authorize!(response.location)

    get "/auth/callback?code=x&state=stale-from-somewhere-else", headers: host

    assert_redirected_to "/"
    refute_empty session_payload
  end

  test "a state replayed once it has been claimed, as a restored tab does, goes on without redeeming again" do
    connect!

    get "/auth", headers: host
    landed = issuer.authorize!(response.location)

    get "/auth/callback?code=#{landed[:code]}&state=#{landed[:state]}", headers: host
    assert_response :redirect
    held = session_payload

    get "/auth/callback?code=#{landed[:code]}&state=#{landed[:state]}", headers: host

    assert_redirected_to "/"
    assert_equal held, session_payload
  end

  test "a forged state is refused and nothing is established" do
    connect!

    get "/auth", headers: host
    landed = issuer.authorize!(response.location)

    get "/auth/callback?code=#{landed[:code]}&state=forged", headers: host

    assert_redirected_to "/auth/"
    assert_empty session_payload

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

  test "a callback with nothing in flight starts sign-in again once, then is refused" do
    connect!

    get "/auth/callback?code=whatever&state=whatever", headers: host
    assert_redirected_to "/auth/"

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
    state = URI.decode_www_form(URI.parse(response.location).query).to_h["state"]

    get "/auth/callback?error=access_denied&error_description=declined&state=#{state}", headers: host

    assert_response :bad_request
    assert_includes response.body, "access_denied"
    assert_empty session_payload
  end

  test "an error on a sign-in this browser did not start never repeats its text" do
    connect!

    get "/auth", headers: host

    get "/auth/callback?error=access_denied&error_description=Call+555-0100+now&state=forged", headers: host

    assert_response :bad_request
    assert_not_includes response.body, "555-0100"
    assert_includes response.body, "invalid_state"

    get "/auth/callback?error=access_denied&error_description=Call+555-0100+now&state=forged",
        headers: host.merge("HTTP_ACCEPT" => "application/json")

    assert_response :bad_request
    assert_equal "invalid_state", json["error"]
    assert_not_includes response.body, "555-0100"
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

  test "a return_to a browser would read as another host is refused" do
    connect!

    [ "/\t/elsewhere.test/steal", "/\n/elsewhere.test/steal", "/a\\..\\/elsewhere.test", "/ /elsewhere.test" ].each do |sent|
      get "/auth?return_to=#{CGI.escape(sent)}", headers: host
      landed = issuer.authorize!(response.location)

      get "/auth/callback?code=#{landed[:code]}&state=#{landed[:state]}", headers: host

      assert_redirected_to "/", "#{sent.inspect} must not survive as a return_to"
    end
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

    post "/auth/logout", headers: host.merge("HTTP_ORIGIN" => origin)

    assert_redirected_to "/"
    assert_empty session_payload

    get "/auth/session", headers: host.merge("HTTP_ACCEPT" => "application/json")

    assert_response :unauthorized
  end

  test "a link on another site cannot sign anybody out" do
    sign_in!
    revoked = issuer.revocations.size

    get "/auth/logout?everywhere=1", headers: host.merge("HTTP_SEC_FETCH_SITE" => "cross-site")

    assert_response :forbidden
    assert_includes response.body, "that request came from another site"
    refute_empty session_payload
    assert_equal revoked, issuer.revocations.size
  end

  test "a form on a sibling site cannot sign anybody out" do
    sign_in!

    post "/auth/logout", headers: host.merge("HTTP_SEC_FETCH_SITE" => "same-site")

    assert_response :forbidden
    refute_empty session_payload
  end

  test "a sign-out whose Origin names another site is refused, whatever its method" do
    sign_in!

    [ "https://elsewhere.test", "null" ].each do |sent|
      delete "/auth/logout", headers: host.merge("HTTP_ORIGIN" => sent, "HTTP_ACCEPT" => "application/json")

      assert_response :forbidden
      assert_equal "invalid_request", json["error"]
    end

    refute_empty session_payload
  end

  test "a sign-out from this app's own pages goes ahead" do
    sign_in!

    delete "/auth/logout", headers: host.merge("HTTP_ORIGIN" => origin, "HTTP_SEC_FETCH_SITE" => "same-origin",
                                               "HTTP_ACCEPT" => "application/json")

    assert_response :success
    assert_empty session_payload
  end

  test "a sign-out typed into the address bar goes ahead" do
    sign_in!

    get "/auth/logout", headers: host.merge("HTTP_SEC_FETCH_SITE" => "none")

    assert_redirected_to "/"
    assert_empty session_payload
  end

  test "a link followed from this app's own pages signs out" do
    sign_in!

    get "/auth/logout", headers: host.merge("HTTP_SEC_FETCH_SITE" => "same-origin")

    assert_redirected_to "/"
    assert_empty session_payload
  end

  test "a link followed by a browser that names no site asks before signing out" do
    sign_in!
    revoked = issuer.revocations.size

    get "/auth/logout", headers: host

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_includes response.body, "<title>Sign out</title>"
    assert_includes response.body, "Select Sign out to finish signing out."
    assert_match %r{<form[^>]*action="/auth/logout"[^>]*method="post"}, response.body
    refute_includes response.body, "everywhere"
    refute_empty session_payload
    assert_equal revoked, issuer.revocations.size
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "DENY", response.headers["X-Frame-Options"]
    assert_equal "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'",
                 response.headers["Content-Security-Policy"]
  end

  test "the question before signing out carries everywhere on to the form" do
    sign_in!

    get "/auth/logout?everywhere=1&return_to=https://elsewhere.test", headers: host

    assert_response :success
    assert_match %r{<form[^>]*action="/auth/logout\?everywhere=1"}, response.body
    refute_includes response.body, "elsewhere.test"
    refute_empty session_payload
  end

  test "answering the question signs out" do
    sign_in!

    get "/auth/logout", headers: host
    post "/auth/logout", headers: host.merge("HTTP_ORIGIN" => origin)

    assert_redirected_to "/"
    assert_empty session_payload
  end

  test "a POST that names no site is refused and keeps the session" do
    sign_in!
    revoked = issuer.revocations.size

    post "/auth/logout", headers: host

    assert_response :forbidden
    assert_includes response.body, "that request came from another site"
    refute_empty session_payload
    assert_equal revoked, issuer.revocations.size
  end

  test "a request for JSON that names no site is told to sign out with a POST" do
    sign_in!

    get "/auth/logout", headers: host.merge("HTTP_ACCEPT" => "application/json")

    assert_response :forbidden
    assert_equal "invalid_request", json["error"]
    assert_equal "sign out with a POST from this site", json["error_description"]
    refute_empty session_payload
  end

  test "signing out drops the local session and leaves the issuer's" do
    sign_in!

    delete "/auth/logout", headers: host.merge("HTTP_ORIGIN" => origin, "HTTP_ACCEPT" => "application/json")

    assert_response :success
    assert_equal false, json["signed_in"]
    assert_nil json["logout_url"], "nothing asked to sign out of masks"
    assert_empty session_payload
  end

  test "signing out revokes the refresh token at the issuer" do
    sign_in!

    held = session_payload["refresh_token"]
    refute_nil held

    delete "/auth/logout", headers: host.merge("HTTP_ORIGIN" => origin, "HTTP_ACCEPT" => "application/json")

    revoked = issuer.revocations.last

    assert_equal held, revoked["token"]
    assert_equal "refresh_token", revoked["token_type_hint"]
  end

  test "signing out everywhere hands back where to end the issuer's session" do
    sign_in!

    delete "/auth/logout?everywhere=1", headers: host.merge("HTTP_ORIGIN" => origin, "HTTP_ACCEPT" => "application/json")

    assert_response :success
    assert_equal false, json["signed_in"]

    query = URI.decode_www_form(URI.parse(json["logout_url"]).query).to_h

    assert json["logout_url"].start_with?("#{issuer.url_for(SUBDOMAIN)}/logout")
    assert_equal "test-client", query["client_id"]
    assert_equal "#{origin}/auth/logout/return", query["post_logout_redirect_uri"],
                 "the handshake registered this as the one place masks sends people after logout"
    refute_empty query["state"]
  end

  test "masks sends somebody who signed out everywhere back to where the app sends people after signing out" do
    configure!(after_sign_out: "/goodbye")

    state = sign_out_everywhere!

    get "/auth/logout/return?state=#{state}", headers: host

    assert_redirected_to "/goodbye"
  end

  test "the return from signing out everywhere is honoured once" do
    state = sign_out_everywhere!

    get "/auth/logout/return?state=#{state}", headers: host
    assert_redirected_to "/"

    get "/auth/logout/return?state=#{state}", headers: host
    assert_response :bad_request
    assert_includes response.body, "invalid_state"
  end

  test "a return from signing out with a state this browser did not send is refused" do
    sign_out_everywhere!

    get "/auth/logout/return?state=forged", headers: host

    assert_response :bad_request
    assert_includes response.body, "invalid_state"
  end

  test "a return from signing out that took too long is refused" do
    state = sign_out_everywhere!

    travel Masks::Client::Tracker::TTL + 1 do
      get "/auth/logout/return?state=#{state}", headers: host
    end

    assert_response :bad_request
    assert_includes response.body, "invalid_state"
  end

  test "a return from signing out goes nowhere but a local path" do
    configure!(after_sign_out: "https://elsewhere.test/")

    state = sign_out_everywhere!

    get "/auth/logout/return?state=#{state}", headers: host

    assert_redirected_to "/"
  end

  test "the handshake callback leaves a sign-out for the sign-out return" do
    state = sign_out_everywhere!
    before = CREDENTIALS[HOST]

    get "/auth/handshake/callback?initial_access_token=whatever&state=#{state}", headers: host

    assert_equal before, CREDENTIALS[HOST]

    get "/auth/logout/return?state=#{state}", headers: host

    assert_redirected_to "/"
  end

  test "a consumer can make signing out mean signing out of masks" do
    Masks::Rails.config.sign_out_of_issuer = true

    sign_in!

    delete "/auth/logout", headers: host.merge("HTTP_ORIGIN" => origin)

    assert_response :redirect
    assert response.location.start_with?("#{issuer.url_for(SUBDOMAIN)}/logout")
    assert_empty session_payload

    query = URI.decode_www_form(URI.parse(response.location).query).to_h

    assert_equal "test-client", query["client_id"]
    assert_equal "#{origin}/auth/logout/return", query["post_logout_redirect_uri"]

    get "/auth/logout/return?state=#{query['state']}", headers: host

    assert_redirected_to "/"
  ensure
    Masks::Rails.config.sign_out_of_issuer = false
  end

  test "an unconnected app offers no logout url, rather than a broken one" do
    delete "/auth/logout?everywhere=1", headers: host.merge("HTTP_ORIGIN" => origin, "HTTP_ACCEPT" => "application/json")

    assert_response :success
    assert_nil json["logout_url"]
  end

  private

    def sign_out_everywhere!
      sign_in!

      delete "/auth/logout?everywhere=1", headers: host.merge("HTTP_ORIGIN" => origin, "HTTP_ACCEPT" => "application/json")

      URI.decode_www_form(URI.parse(json["logout_url"]).query).to_h.fetch("state")
    end

    def session_payload
      held_session
    end
end
