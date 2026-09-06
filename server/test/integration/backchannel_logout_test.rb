require "test_helper"

class BackchannelLogoutTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  LOGOUT_URI = "https://probe.example.com/logout/backchannel".freeze

  setup do
    @actor = create_actor(@tenant, nickname: "owner")
    host! host_for(@tenant)

    @registration = register(backchannel_logout_uri: LOGOUT_URI)
  end

  def delivered
    @delivered ||= []
  end

  def catching(status: 200, &block)
    stub_request(:post, LOGOUT_URI).to_return(status: status) do |request|
      delivered << Rack::Utils.parse_query(request.body)["logout_token"]
      { status: status }
    end

    perform_enqueued_jobs(&block)
  end

  def claims_in_logout(jwt)
    JWT.decode(
      jwt, nil, true,
      algorithms: [ SigningKey::ALGORITHM ],
      jwks: issuer_for(@tenant).jwks,
      iss: issuer_for(@tenant).url, verify_iss: true
    ).first
  end

  test "discovery says the back channel is there and carries a session id" do
    get "/.well-known/openid-configuration"

    body = JSON.parse(response.body)

    assert body["backchannel_logout_supported"]
    assert body["backchannel_logout_session_supported"]
    assert_includes body["claims_supported"], "sid"
  end

  test "a registered logout uri comes back in the client's metadata" do
    assert_equal LOGOUT_URI, @registration["backchannel_logout_uri"]
  end

  test "an id token names the session it was issued in" do
    granted = access_token_for(actor: @actor, registration: @registration)

    sid = claims_in(granted["id_token"])["sid"]

    assert sid.present?, "an id token has to carry sid for session logout to mean anything"
    assert_equal sid, within(@tenant) { Session.live.first.uuid }
  end

  test "signing out posts a signed logout token to the client that was signed in" do
    granted = access_token_for(actor: @actor, registration: @registration)
    sid = claims_in(granted["id_token"])["sid"]

    catching { delete "/login" }

    assert_equal 1, delivered.length, "the one client with a logout uri hears about it"

    claims = claims_in_logout(delivered.first)

    assert_equal @actor.uuid, claims["sub"]
    assert_equal sid, claims["sid"]
    assert_equal @registration["client_id"], claims["aud"]
    assert_equal({ Issuer::LOGOUT_EVENT => {} }, claims["events"])
    assert claims["jti"].present?
    assert_nil claims["nonce"], "a logout token must not carry a nonce"
  end

  test "a client with no logout uri is not called" do
    quiet = register(client_name: "Quiet")

    access_token_for(actor: @actor, registration: quiet)

    catching { delete "/login" }

    assert_equal 0, delivered.length
  end

  test "a client the session never signed into is not called" do
    other = create_actor(@tenant, nickname: "other")

    access_token_for(actor: @actor, registration: @registration)

    signed_out = within(@tenant) { Session.live.find_by(actor_id: other.id) }

    assert_nil signed_out, "the other account never signed in"

    catching { within(@tenant) { Session.live.first.revoke! } }

    assert_equal 1, delivered.length
  end

  test "the end session endpoint tells the client too" do
    granted = access_token_for(actor: @actor, registration: @registration)

    catching do
      post "/logout", params: { id_token_hint: granted["id_token"] }
    end

    assert_response :redirect
    assert_equal 1, delivered.length
  end

  test "an administrator revoking a session reaches the client as well" do
    access_token_for(actor: @actor, registration: @registration)

    catching { within(@tenant) { Session.live.first.revoke! } }

    assert_equal 1, delivered.length
  end

  test "a session already revoked is not announced twice" do
    access_token_for(actor: @actor, registration: @registration)

    catching do
      within(@tenant) do
        held = Session.live.first
        held.revoke!
        held.revoke!
      end
    end

    assert_equal 1, delivered.length
  end

  test "a client that refuses the token is refused back, so the job retries" do
    stub_request(:post, LOGOUT_URI).to_return(status: 500)

    client = within(@tenant) { Client.find_by(client_id: @registration["client_id"]) }

    assert_raises(BackchannelLogout::Refused) do
      within(@tenant) { BackchannelLogout.deliver!(client, "not-a-real-token") }
    end
  end

  test "a client that cannot be reached is refused back too" do
    client = within(@tenant) { Client.find_by(client_id: @registration["client_id"]) }

    assert_raises(BackchannelLogout::Refused) do
      within(@tenant) { BackchannelLogout.deliver!(client, "not-a-real-token") }
    end
  end

  test "a logout uri with a fragment is refused at registration" do
    body = register(client_name: "Fragmentary", backchannel_logout_uri: "#{LOGOUT_URI}#here")

    assert_equal "invalid_client_metadata", body["error"]
    assert_match(/fragment/, body["error_description"])
  end
end
