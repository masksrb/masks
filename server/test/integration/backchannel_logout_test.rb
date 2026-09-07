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

  test "a client that never answers is written down once the retries run out" do
    stub_request(:post, LOGOUT_URI).to_return(status: 500)

    access_token_for(actor: @actor, registration: @registration)

    perform_enqueued_jobs do
      within(@tenant) { Session.live.first.revoke! }
    rescue BackchannelLogout::Refused
      nil
    end

    said, named = within(@tenant) do
      held = Event.where(action: Event::LOGOUT_UNDELIVERED).first

      [ held, held&.client&.client_id ]
    end

    assert_not_nil said, "an application that never heard is the thing to know about"
    assert_equal @actor.id, said.actor_id
    assert_equal @registration["client_id"], named
    assert_match(/500/, said.details["said"])
  end

  test "a logout uri with a fragment is refused at registration" do
    body = register(client_name: "Fragmentary", backchannel_logout_uri: "#{LOGOUT_URI}#here")

    assert_equal "invalid_client_metadata", body["error"]
    assert_match(/fragment/, body["error_description"])
  end

  def registered_client
    within(@tenant) { Client.find_by(client_id: @registration["client_id"]) }
  end

  def deployed
    Rails.env.define_singleton_method(:local?) { false }

    yield
  ensure
    Rails.env.singleton_class.remove_method(:local?)
  end

  def resolving(address)
    held = [ Addrinfo.tcp(address, 443) ]
    original = Addrinfo.method(:getaddrinfo)

    Addrinfo.define_singleton_method(:getaddrinfo) { |*| held }

    yield
  ensure
    Addrinfo.define_singleton_method(:getaddrinfo, original)
  end

  test "a self-registered client may not aim the back channel at loopback" do
    deployed do
      client = registered_client
      client.backchannel_logout_uri = "http://127.0.0.1:9200/_cluster/settings"

      assert_not client.valid?
      assert_match(/loopback/, client.errors[:backchannel_logout_uri].join("; "))
    end
  end

  test "a self-registered client may not aim the back channel over plain http" do
    deployed do
      client = registered_client
      client.backchannel_logout_uri = "http://probe.example.com/logout/backchannel"

      assert_not client.valid?
      assert_match(/https/, client.errors[:backchannel_logout_uri].join("; "))
    end
  end

  test "a self-registered client is not called at an address inside the network" do
    deployed do
      resolving("10.1.2.3") do
        error = assert_raises(BackchannelLogout::Refused) do
          BackchannelLogout.deliver!(registered_client, "a-logout-token")
        end

        assert_match(/will not call/, error.message)
      end
    end
  end

  test "a self-registered client is still called at an address of its own" do
    stub_request(:post, LOGOUT_URI).to_return(status: 200)

    deployed do
      resolving("93.184.216.34") do
        assert BackchannelLogout.deliver!(registered_client, "a-logout-token")
      end
    end
  end
end
