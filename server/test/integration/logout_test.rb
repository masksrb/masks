require "test_helper"

class LogoutTest < ActionDispatch::IntegrationTest
  BACK = "https://app.example.com/signed-out".freeze

  setup do
    host! host_for(@tenant)
    @actor = create_actor(@tenant)
    @client = create_client(
      @tenant,
      client_id: SecureRandom.uuid,
      redirect_uris: [ "https://app.example.com/cb" ],
      post_logout_redirect_uris: [ BACK ]
    )
  end

  def signed_in
    sign_in_as(@actor)
    assert signed_in?
  end

  def signed_in?
    get "/"
    response.body.include?("id=\"account\"")
  end

  def hint(audience: @client.client_id, subject: @actor.uuid)
    within(@tenant) do
      Issuer.new(@tenant, origin_for(@tenant)).sign(
        "iss" => origin_for(@tenant), "sub" => subject, "aud" => audience,
        "exp" => 1.hour.ago.to_i, "iat" => 2.hours.ago.to_i
      )
    end
  end

  test "discovery says what this issuer can and cannot do about logout" do
    get "/.well-known/openid-configuration"

    document = JSON.parse(response.body)

    assert_equal "#{origin_for(@tenant)}/logout", document["end_session_endpoint"]
    assert_equal false, document["frontchannel_logout_supported"]
    assert_equal true, document["backchannel_logout_supported"]
    assert_equal true, document["backchannel_logout_session_supported"]
  end

  test "an id_token_hint proves who is asking, so the session ends without a click" do
    signed_in

    get "/logout", params: { id_token_hint: hint, post_logout_redirect_uri: BACK, state: "xyz" }

    assert_redirected_to "#{BACK}?state=xyz"
    assert_not signed_in?
  end

  test "an expired id_token_hint is still a valid hint" do
    signed_in

    get "/logout", params: { id_token_hint: hint }

    assert_response :redirect
    assert_not signed_in?
  end

  test "without a hint a person is asked rather than signed out by a link" do
    signed_in

    get "/logout", params: { client_id: @client.client_id, post_logout_redirect_uri: BACK }

    assert_response :success
    assert_match "Sign out?", response.body
    assert signed_in?, "a GET nobody confirmed must not end the session"
  end

  test "confirming it ends the session and goes back where the client asked" do
    signed_in

    delete "/logout", params: { client_id: @client.client_id,
                                post_logout_redirect_uri: BACK, state: "xyz" }

    assert_redirected_to "#{BACK}?state=xyz"
    assert_not signed_in?
  end

  test "an unregistered post_logout_redirect_uri is refused rather than followed" do
    signed_in

    get "/logout", params: { id_token_hint: hint,
                             post_logout_redirect_uri: "https://elsewhere.example.com/" }

    assert_response :bad_request
    assert_match "invalid_request", response.body
    assert signed_in?, "a refused logout must not have ended the session anyway"
  end

  test "a post_logout_redirect_uri with nothing to check it against is refused" do
    signed_in

    get "/logout", params: { post_logout_redirect_uri: BACK }

    assert_response :bad_request
    assert_match "invalid_request", response.body
  end

  test "an id_token_hint this issuer did not sign is refused" do
    signed_in

    forged = JWT.encode({ "iss" => origin_for(@tenant), "aud" => @client.client_id },
                        OpenSSL::PKey::RSA.generate(2048), "RS256")

    get "/logout", params: { id_token_hint: forged }

    assert_response :bad_request
    assert signed_in?
  end

  test "an id_token_hint from another tenant is refused here" do
    elsewhere = Tenant.create!(subdomain: "acme-#{SecureRandom.hex(4)}", name: "Acme")
    theirs = within(elsewhere) do
      Issuer.new(elsewhere, origin_for(elsewhere)).sign(
        "iss" => origin_for(elsewhere), "sub" => "x", "aud" => @client.client_id,
        "exp" => 1.hour.from_now.to_i
      )
    end

    signed_in

    get "/logout", params: { id_token_hint: theirs }

    assert_response :bad_request
    assert signed_in?
  end

  test "signing out with nowhere to go lands on the sign-in page" do
    signed_in

    get "/logout", params: { id_token_hint: hint }

    assert_redirected_to login_path
    assert_not signed_in?
  end

  test "a client registers where it may be sent back to" do
    body = register(post_logout_redirect_uris: [ "https://probe.example.com/out" ])

    assert_response :created
    assert_equal [ "https://probe.example.com/out" ], body["post_logout_redirect_uris"]
  end
end
