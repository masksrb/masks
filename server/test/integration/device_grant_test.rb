require "test_helper"

class DeviceGrantTest < ActionDispatch::IntegrationTest
  GRANT = DeviceGrant::GRANT_TYPE

  setup do
    @actor = create_actor(email: "owner@example.com")
    host! host_for(@tenant)
    @registration = register(
      @tenant,
      grant_types: [ "authorization_code", "refresh_token", GRANT ]
    )
  end

  test "the server says where a device asks for a code" do
    get "/.well-known/openid-configuration"

    held = JSON.parse(response.body)

    assert_equal "#{origin_for(@tenant)}/device_authorization", held["device_authorization_endpoint"]
    assert_includes held["grant_types_supported"], GRANT
  end

  test "a device is given a code, and a place to send the person" do
    held = ask

    assert held["device_code"].present?
    assert_match(/\A[BCDFGHJKLMNPQRSTVWXZ]{4}-[BCDFGHJKLMNPQRSTVWXZ]{4}\z/, held["user_code"])
    assert_equal "#{origin_for(@tenant)}/device", held["verification_uri"]
    assert_includes held["verification_uri_complete"], CGI.escape(held["user_code"])
    assert_equal DeviceGrant::INTERVAL, held["interval"]
    assert held["expires_in"].positive?
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "a device waits while nobody has answered" do
    held = ask
    answer = poll(held["device_code"])

    assert_equal "authorization_pending", answer["error"]
  end

  test "a device that polls too fast is told to slow down" do
    held = ask

    poll(held["device_code"])

    answer = poll(held["device_code"])

    assert_equal "slow_down", answer["error"]
  end

  test "a device is signed in once somebody types its code" do
    held = ask

    approve!(held["user_code"])

    assert_response :success
    assert_match(/signed in/i, response.body)

    travel DeviceGrant::INTERVAL.seconds + 1.second

    answer = poll(held["device_code"])

    assert answer["access_token"].present?
    assert_equal "Bearer", answer["token_type"]
    assert_equal @actor.uuid, claims_in(answer["access_token"])["sub"]
    assert_equal @actor.uuid, claims_in(answer["id_token"])["sub"]
    assert answer["refresh_token"].present?
  end

  test "the token a device is given carries the scopes the person allowed" do
    held = ask(scope: "openid profile email offline_access")

    approve!(held["user_code"])
    travel DeviceGrant::INTERVAL.seconds + 1.second

    answer = poll(held["device_code"])

    assert_equal "email offline_access openid profile", answer["scope"]
  end

  test "a device code is good for one token and no more" do
    held = ask

    approve!(held["user_code"])
    travel DeviceGrant::INTERVAL.seconds + 1.second

    assert poll(held["device_code"])["access_token"].present?

    travel DeviceGrant::INTERVAL.seconds + 1.second

    answer = poll(held["device_code"])

    assert_equal "invalid_grant", answer["error"]
  end

  test "a device is turned away when the person declines" do
    held = ask

    sign_in_as(@actor)
    get "/device?#{URI.encode_www_form(user_code: held['user_code'])}"

    assert awaiting_consent?

    decline!

    assert_match(/nothing was signed in/i, response.body)

    travel DeviceGrant::INTERVAL.seconds + 1.second

    answer = poll(held["device_code"])

    assert_equal "access_denied", answer["error"]
  end

  test "a device code stops working once it has expired" do
    held = ask

    travel DeviceGrant.lifetime + 1.minute

    answer = poll(held["device_code"])

    assert_equal "expired_token", answer["error"]
  end

  test "a user code stops working once it has expired" do
    held = ask

    travel DeviceGrant.lifetime + 1.minute

    sign_in_as(@actor)
    get "/device?#{URI.encode_www_form(user_code: held['user_code'])}"

    assert_response :success
    assert_match(/not one this server is waiting on/i, response.body)
  end

  test "a device code belongs to the client that asked for it" do
    held = ask
    other = register(@tenant, grant_types: [ "authorization_code", GRANT ], client_name: "Other")

    answer = token(
      grant_type: GRANT,
      device_code: held["device_code"],
      client_id: other["client_id"],
      client_secret: other["client_secret"]
    )

    assert_equal "invalid_grant", answer["error"]
  end

  test "a client that never registered the device grant may not ask for a code" do
    plain = register(@tenant, client_name: "Plain")

    post "/device_authorization",
         params: { client_id: plain["client_id"], client_secret: plain["client_secret"], scope: "openid" }

    assert_response :bad_request
    assert_equal "unauthorized_client", JSON.parse(response.body)["error"]
  end

  test "a client that never registered the device grant may not redeem a code" do
    held = ask
    plain = register(@tenant, client_name: "Plain")

    answer = token(
      grant_type: GRANT,
      device_code: held["device_code"],
      client_id: plain["client_id"],
      client_secret: plain["client_secret"]
    )

    assert_equal "unauthorized_client", answer["error"]
  end

  test "a device code that was never issued is refused" do
    answer = poll("not-a-device-code")

    assert_equal "invalid_grant", answer["error"]
  end

  test "a code typed in wrong asks again rather than saying what was wrong" do
    sign_in_as(@actor)

    get "/device?#{URI.encode_www_form(user_code: 'BCDF-GHJK')}"

    assert_response :success
    assert_match(/not one this server is waiting on/i, response.body)
  end

  test "the page asks for a code when none was typed" do
    get "/device"

    assert_response :success
    assert_select "form#device"
  end

  test "the form sends the code on to the page that answers it" do
    held = ask

    post "/device", params: { user_code: held["user_code"] }

    assert_redirected_to device_verification_path(user_code: held["user_code"])
  end

  test "a code is read however it was typed" do
    held = ask
    typed = held["user_code"].delete("-").downcase

    approve!(typed)

    assert_response :success
    assert_match(/signed in/i, response.body)
  end

  test "two devices waiting on one client are answered apart" do
    here = ask
    there = ask

    assert_not_equal here["user_code"], there["user_code"]

    approve!(here["user_code"])

    travel DeviceGrant::INTERVAL.seconds + 1.second

    assert poll(here["device_code"])["access_token"].present?
    assert_equal "authorization_pending", poll(there["device_code"])["error"]
  end

  test "a device asking for a scope its client may not have is refused" do
    post "/device_authorization",
         params: {
           client_id: @registration["client_id"],
           client_secret: @registration["client_secret"],
           scope: Scopes::MANAGE
         }

    assert_response :bad_request
    assert_equal "invalid_scope", JSON.parse(response.body)["error"]
  end

  test "signing a device in is written down" do
    held = ask

    approve!(held["user_code"])

    actions = within { Event.where(client_id: Client.find_by(client_id: @registration["client_id"]).id).pluck(:action) }

    assert_includes actions, Event::DEVICE_CODE_ISSUED
    assert_includes actions, Event::DEVICE_CODE_APPROVED
  end

  private

    def ask(scope: "openid profile email offline_access")
      post "/device_authorization",
           params: {
             client_id: @registration["client_id"],
             client_secret: @registration["client_secret"],
             scope: scope
           }

      assert_response :success

      JSON.parse(response.body)
    end

    def poll(device_code)
      token(
        grant_type: GRANT,
        device_code: device_code,
        client_id: @registration["client_id"],
        client_secret: @registration["client_secret"]
      )
    end

    def approve!(user_code)
      sign_in_as(@actor)

      get "/device?#{URI.encode_www_form(user_code: user_code)}"

      consent! if awaiting_consent?

      response
    end
end
