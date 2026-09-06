require_relative "test_helper"

class HandshakeTest < EngineIntegrationTest
  test "an app nobody has connected starts the handshake rather than asking first" do
    get "/auth/handshake", headers: host

    assert_response :redirect
    assert response.location.start_with?("#{issuer.url_for(SUBDOMAIN)}/handshake")
  end

  test "an app configured too little to shake hands is told so rather than sent away" do
    configure!(resource: nil)

    get "/auth/handshake", headers: host

    assert_response :bad_request
    assert_includes response.body, "could not be connected"
    assert_includes response.body, "resource is not set"
  end

  test "an unconnected app sends a browser to the handshake rather than a login it cannot run" do
    get "/dashboard", headers: host

    assert_redirected_to "/auth/handshake"
  end

  test "starting the handshake sends the browser to the endpoint discovery advertises" do
    post "/auth/handshake", headers: host

    assert_response :redirect
    assert response.location.start_with?("#{issuer.url_for(SUBDOMAIN)}/handshake")
  end

  test "the connect url names one origin throughout, and the scopes it wants" do
    post "/auth/handshake", headers: host

    query = URI.decode_www_form(URI.parse(response.location).query)
    held = query.each_with_object(Hash.new { |h, k| h[k] = [] }) { |(k, v), out| out[k] << v }

    assert_equal [ "#{origin}/mcp" ], held["resource"]
    assert_equal [ "#{origin}/auth/callback" ], held["redirect_uris"]
    assert_equal [ "#{origin}/auth/handshake/callback" ], held["return_to"]
    assert_includes held["scope"].first.split(" "), "catalog:read"
    assert_equal [ "Catalog" ], held["client_name"]
    refute_empty held["state"]
  end

  test "approving redeems the token server to server and hands the registration to the store" do
    shake_hands!

    assert_redirected_to "/auth/"

    held = CREDENTIALS[HOST]

    refute_nil held
    refute_nil held[:client_id]
    refute_nil held[:client_secret]
    refute_nil held[:registration_access_token]
    refute_nil held[:registration_client_uri]
  end

  test "what is registered is what the connect url asked for" do
    shake_hands!

    sent = issuer.last_registration

    assert_equal [ "#{origin}/auth/callback" ], sent["redirect_uris"]
    assert_equal "client_secret_basic", sent["token_endpoint_auth_method"]
    assert_includes sent["grant_types"], "refresh_token"
    assert_equal "Catalog", sent["client_name"]
  end

  test "the secret never travels the browser" do
    started = shake_hands!

    refute_includes started.keys, "client_secret"
    refute_includes response.body, CREDENTIALS[HOST][:client_secret]
  end

  test "a callback with no handshake in flight is refused" do
    get "/auth/handshake/callback?initial_access_token=whatever&state=whatever", headers: host

    assert_response :bad_request
    assert_includes response.body, "could not be connected"
    assert_nil CREDENTIALS[HOST]
  end

  test "a callback whose state does not match this browser is refused" do
    post "/auth/handshake", headers: host

    token = issuer.approve!(SUBDOMAIN)

    get "/auth/handshake/callback?initial_access_token=#{token}&state=forged", headers: host

    assert_response :bad_request
    assert_nil CREDENTIALS[HOST]
  end

  test "a callback naming another issuer is refused before anything is redeemed" do
    post "/auth/handshake", headers: host

    started = URI.decode_www_form(URI.parse(response.location).query).to_h
    token = issuer.approve!(SUBDOMAIN)

    get "/auth/handshake/callback?initial_access_token=#{token}&state=#{started['state']}" \
        "&iss=#{CGI.escape('http://elsewhere.test')}", headers: host

    assert_response :bad_request
    assert_nil CREDENTIALS[HOST]
  end

  test "a refusal from the issuer is rendered rather than stored" do
    post "/auth/handshake", headers: host

    started = URI.decode_www_form(URI.parse(response.location).query).to_h

    get "/auth/handshake/callback?error=access_denied&error_description=declined" \
        "&state=#{started['state']}", headers: host

    assert_response :bad_request
    assert_includes response.body, "access_denied"
    assert_nil CREDENTIALS[HOST]
  end

  test "a token the issuer never approved is refused" do
    post "/auth/handshake", headers: host

    started = URI.decode_www_form(URI.parse(response.location).query).to_h

    get "/auth/handshake/callback?initial_access_token=never-approved&state=#{started['state']}", headers: host

    assert_response :bad_request
    assert_nil CREDENTIALS[HOST]
  end

  test "a connected app does not offer the handshake to a browser that is not signed in" do
    connect!

    get "/auth/handshake", headers: host
    assert_redirected_to "/"

    post "/auth/handshake", headers: host
    assert_redirected_to "/"
  end

  test "a connected app offers a rotation to somebody signed in, not a first connect" do
    sign_in!

    get "/auth/handshake", headers: host

    assert_response :success
    assert_includes response.body, "Reconnect it"
    assert_includes response.body, "Disconnect it"
    assert_not_includes response.body, "has not been connected yet"
  end

  test "reconnecting runs the same handshake and replaces what is held" do
    sign_in!

    before = CREDENTIALS[HOST][:client_id]
    registrations = issuer.registrations.length

    shake_hands!

    assert_response :redirect
    assert_equal registrations + 1, issuer.registrations.length
    assert_not_equal before, CREDENTIALS[HOST][:client_id],
                     "a second run must replace the credentials, not leave the old pair"
    assert CREDENTIALS[HOST][:registration_access_token].present?
  end

  test "disconnecting deletes the registration upstream and drops what is held" do
    sign_in!
    shake_hands!

    held = CREDENTIALS[HOST]
    assert held[:registration_access_token].present?

    delete "/auth/handshake", headers: host

    assert_redirected_to "/auth/handshake"
    assert_nil CREDENTIALS[HOST]

    deleted = issuer.deletions.last

    assert_equal held[:client_id], deleted[:client_id]
    assert_equal held[:registration_access_token], deleted[:token],
                 "RFC 7592 delete is authenticated by the registration access token"
  end

  test "disconnecting drops what is held even when the issuer has forgotten the registration" do
    sign_in!
    shake_hands!

    issuer.forgotten = true

    delete "/auth/handshake", headers: host

    assert_redirected_to "/auth/handshake"
    assert_nil CREDENTIALS[HOST],
               "a registration the issuer no longer knows must not strand the app that holds it"
  end

  test "an issuer that cannot be reached does not cost an app its registration" do
    sign_in!

    CREDENTIALS.hold!(
      HOST,
      client_id: "test-client",
      client_secret: "test-secret",
      registration_access_token: "held",
      registration_client_uri: "http://127.0.0.1:1/#{SUBDOMAIN}/register/test-client"
    )

    delete "/auth/handshake", headers: host

    assert_response :bad_request
    refute_nil CREDENTIALS[HOST],
               "an issuer that is merely down is a reason to try again, not to forget"
  end

  test "disconnecting is refused to a browser that is not signed in" do
    connect!

    delete "/auth/handshake", headers: host

    assert_redirected_to "/"
    assert CREDENTIALS[HOST].present?
  end

  test "an app whose store cannot forget is not offered a button that would fail" do
    configure!(forget: nil)
    sign_in!

    get "/auth/handshake", headers: host

    assert_includes response.body, "Reconnect it"
    assert_not_includes response.body, "Disconnect it"
  end
end
