require "test_helper"

class DevicesTest < ActionDispatch::IntegrationTest
  CHROME = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
           "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze

  setup do
    host! host_for(@tenant)
    @actor = create_actor(@tenant)
    @totp = enable_otp(@actor)
  end

  def browser
    { "HTTP_USER_AGENT" => CHROME }
  end

  def event(name, **updates)
    post "/login", params: { event: name }.merge(updates), as: :json, headers: browser

    JSON.parse(response.body)
  end

  def to_second_factor
    event("identify", identifier: @actor.nickname)
    event("password", password: "password")
  end

  def devices
    within(@tenant) { Device.newest_first.to_a }
  end

  def forget_browser
    delete "/login", headers: browser
    cookies.delete(:masks_session)
    cookies.delete(Device::COOKIE)
  end

  test "signing in records the device the session came from" do
    to_second_factor
    settled = event("otp", code: @totp.now)

    assert settled["settled"], settled.inspect
    assert_equal 1, devices.length

    device = devices.first

    assert_equal "Chrome on Mac", device.label
    assert_equal CHROME, device.user_agent

    within(@tenant) do
      session = Session.live.find_by(actor: @actor)

      assert_equal device.id, session.device_id
      assert_equal device.version, session.device_version
    end
  end

  test "an anonymous request that never signs in leaves no device behind" do
    get "/login", headers: browser

    assert_response :success
    assert_empty devices
  end

  test "signing in again from the same browser reuses the device" do
    to_second_factor
    event("otp", code: @totp.now)

    delete "/login"

    to_second_factor
    event("otp", code: @totp.now)

    assert_equal 1, devices.length
  end

  test "a remembered device skips the second factor, and says so in amr" do
    to_second_factor

    assert_equal "second-factor", event("otp", code: "000000")["prompt"]

    settled = event("otp", code: @totp.now, remember: true)

    assert settled["settled"], settled.inspect

    delete "/login"
    cookies.delete(:masks_session)

    settled = to_second_factor

    assert settled["settled"], settled.inspect

    within(@tenant) do
      session = Session.live.where(actor: @actor).order(:created_at).last

      assert_includes session.amr, "mfa"
      assert_not_includes session.amr, "otp"
    end
  end

  test "without the tick the second factor is asked for again on the same device" do
    to_second_factor
    event("otp", code: @totp.now)

    delete "/login"
    cookies.delete(:masks_session)

    assert_equal "second-factor", to_second_factor["prompt"]
  end

  test "a device that is trusted here is not trusted from another browser" do
    to_second_factor
    event("otp", code: @totp.now, remember: true)

    forget_browser

    assert_equal "second-factor", to_second_factor["prompt"]
  end

  test "signing a device out from the account page revokes it and asks for everything again" do
    to_second_factor
    event("otp", code: @totp.now, remember: true)

    device = devices.first

    delete "/account/devices/#{device.id}", headers: browser

    assert_redirected_to login_path

    within(@tenant) do
      assert_empty Session.live.where(actor: @actor)
      assert_not DeviceFactor.satisfied?(device: device.reload, actor: @actor)
    end

    assert_equal "second-factor", to_second_factor["prompt"]
  end

  test "a device can be named from the account page" do
    to_second_factor
    event("otp", code: @totp.now)

    device = devices.first

    patch "/account/devices/#{device.id}", params: { name: "The kitchen laptop" }, headers: browser

    assert_redirected_to root_path
    assert_equal "The kitchen laptop", within(@tenant) { device.reload.label }
  end

  test "a blocked device is refused, and cannot sign in again" do
    to_second_factor
    event("otp", code: @totp.now)

    device = devices.first
    within(@tenant) { device.block! }

    get "/", headers: browser

    assert_response :forbidden

    assert_equal "this device has been blocked", response.body
  end

  test "a token carries the device that authorized it" do
    registration = register(@tenant)

    to_second_factor
    event("otp", code: @totp.now)

    authorize(client_id: registration["client_id"], scope: "openid profile email offline_access")
    consent! if awaiting_consent?

    code = code_from
    granted = token(
      grant_type: "authorization_code",
      code: code,
      redirect_uri: OidcFlow::REDIRECT_URI,
      code_verifier: verifier,
      client_id: registration["client_id"],
      client_secret: registration["client_secret"]
    )

    assert granted["access_token"].present?, granted.inspect

    device = devices.first

    within(@tenant) do
      assert_equal [ device.id ], Token.where(actor: @actor).where.not(device_id: nil).pluck(:device_id).uniq
      assert_equal device.id, RefreshToken.where(actor: @actor).first&.device_id
    end
  end

  test "one actor's devices are not another's" do
    to_second_factor
    event("otp", code: @totp.now)

    stranger = create_actor(@tenant, nickname: "stranger")

    within(@tenant) do
      assert_equal 1, @actor.devices.count
      assert_equal 0, stranger.devices.count
    end
  end
end
