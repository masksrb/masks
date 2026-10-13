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
      typ: "logout+jwt",
      **{
        "sid" => "session-1",
        "events" => { EVENT => {} },
        "scope" => nil
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
      subdomain: SUBDOMAIN, audience: "someone-else", subject: "actor-1", typ: "logout+jwt",
      "events" => { EVENT => {} }, "scope" => nil
    )

    assert_response :bad_request
    assert_empty @heard
  end

  test "a token about something other than a logout is refused" do
    post_logout token("events" => { "http://schemas.openid.net/event/other" => {} })

    assert_response :bad_request
    assert_empty @heard
  end

  test "an app that says nothing about logout still signs the session out" do
    Masks::Rails.config.logged_out = nil

    post_logout token

    assert_response :ok
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "a logout token without an expiry is refused" do
    post_logout token("exp" => nil)

    assert_response :bad_request
    assert_empty @heard
  end

  test "a logout token is accepted once" do
    held = token

    post_logout held

    assert_response :ok

    post_logout held

    assert_response :bad_request
    assert_match "already used", JSON.parse(response.body)["error_description"]
    assert_equal 1, @heard.length
  end

  test "a cache that cannot keep the logout answers 503, so masks sends the token again" do
    failing = ActiveSupport::Cache::MemoryStore.new
    failing.instance_variable_set(:@refusing, true)
    def failing.write(key, value, **options) = options[:unless_exist] || !@refusing ? super : false
    Masks::Rails.config.cache = failing
    held = token

    post_logout held

    assert_response :service_unavailable
    assert_equal "temporarily_unavailable", JSON.parse(response.body)["error"]
    assert_empty @heard

    failing.instance_variable_set(:@refusing, false)

    post_logout held

    assert_response :ok
  end

  test "the browser signed in to the session masks ended is signed out at its next request" do
    sign_in!

    post_logout token

    get "/auth/session", headers: { "HOST" => HOST, "HTTP_ACCEPT" => "application/json" }

    assert_response :unauthorized
    assert_empty held_session
  end

  test "a logout that names only the person signs out every session of theirs" do
    sign_in!

    post_logout token("sid" => nil)

    get "/dashboard", headers: { "HOST" => HOST }

    assert_redirected_to "/auth/"
  end

  test "a logout of another session leaves this one signed in" do
    sign_in!

    post_logout token("sid" => "session-2")

    get "/auth/session", headers: { "HOST" => HOST, "HTTP_ACCEPT" => "application/json" }

    assert_response :success
  end

  test "signing in again after a logout starts a session the logout does not reach" do
    sign_in!
    post_logout token

    travel 1.second do
      sign_in!

      get "/auth/session", headers: { "HOST" => HOST, "HTTP_ACCEPT" => "application/json" }
    end

    assert_response :success
  end

  test "the endpoint takes no csrf token, because the issuer has no browser" do
    post_logout token

    assert_response :ok
  end
end

class BackchannelLogoutRegistrationTest < EngineTest
  def request
    ActionDispatch::TestRequest.create.tap { |held| held.host = HOST }
  end

  test "the handshake registers where masks sends logout tokens" do
    handshake = Masks::Rails.config.handshake_for(request)

    assert_equal "#{request.base_url}/auth/logout/backchannel",
                 handshake.backchannel_logout_uri
    assert_includes handshake.url(state: "s-1"), "backchannel_logout_uri"
  end

  test "an issuer that does not send logout tokens is not told where to send them" do
    issuer.backchannel = false

    handshake = Masks::Rails.config.handshake_for(request)

    assert_nil handshake.backchannel_logout_uri
    refute_includes handshake.url(state: "s-1"), "backchannel_logout_uri"
  end
end
