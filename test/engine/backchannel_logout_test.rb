require_relative "test_helper"

class BackchannelLogoutTest < EngineIntegrationTest
  EVENT = Masks::Client::Logout::EVENT
  PATH = "/auth/logout/backchannel".freeze

  setup do
    @heard = []

    connect!
    configure!
    Masks::Rails.config.logged_out = ->(logout) { @heard << logout }
  end

  teardown { Masks::Rails.config.logged_out = nil }

  def token(**overrides)
    issuer.mint(
      subdomain: SUBDOMAIN,
      audience: "test-client",
      subject: "actor-1",
      **{
        "sid" => "session-1",
        "events" => { EVENT => {} },
        "scope" => nil,
        "exp" => nil
      }.merge(overrides)
    )
  end

  def post_logout(value)
    post PATH, params: { logout_token: value }, headers: { "HOST" => HOST }
  end

  test "a token the issuer signed for this app is accepted, and the app is told" do
    post_logout token

    assert_response :ok
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal 1, @heard.length
    assert_equal "actor-1", @heard.first.subject
    assert_equal "session-1", @heard.first.sid
  end

  test "a request with no token is refused" do
    post PATH, headers: { "HOST" => HOST }

    assert_response :bad_request
    assert_equal "invalid_request", JSON.parse(response.body)["error"]
    assert_empty @heard
  end

  test "an id token in place of a logout token is refused" do
    post_logout token("nonce" => "n-1")

    assert_response :bad_request
    assert_empty @heard
  end

  test "a token for another application is refused" do
    post_logout issuer.mint(
      subdomain: SUBDOMAIN, audience: "someone-else", subject: "actor-1",
      "events" => { EVENT => {} }, "scope" => nil, "exp" => nil
    )

    assert_response :bad_request
    assert_empty @heard
  end

  test "a token about something other than a logout is refused" do
    post_logout token("events" => { "http://schemas.openid.net/event/other" => {} })

    assert_response :bad_request
    assert_empty @heard
  end

  test "the endpoint takes no csrf token, because the issuer has no browser" do
    post_logout token

    assert_response :ok
  end
end

class BackchannelLogoutRegistrationTest < EngineTest
  test "an app that says what to do about logout registers where to be told" do
    Masks::Rails.config.logged_out = ->(logout) { logout }

    request = ActionDispatch::TestRequest.create
    request.host = HOST

    handshake = Masks::Rails.config.handshake_for(request)

    assert_equal "#{request.base_url}/auth/logout/backchannel",
                 handshake.backchannel_logout_uri
    assert_includes handshake.url(state: "s-1"), "backchannel_logout_uri"
  ensure
    Masks::Rails.config.logged_out = nil
  end

  test "an app that does not is not registered for it" do
    request = ActionDispatch::TestRequest.create
    request.host = HOST

    assert_nil Masks::Rails.config.handshake_for(request).backchannel_logout_uri
  end
end
