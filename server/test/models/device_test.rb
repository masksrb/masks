require "test_helper"

class DeviceTest < ActiveSupport::TestCase
  CHROME = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
           "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze

  setup do
    @actor = create_actor(@tenant)
  end

  test "identifying without an id mints one, and identifying with it returns the same row" do
    first = within { Device.identify(nil, user_agent: CHROME, ip_address: "203.0.113.7") }
    again = within { Device.identify(first.public_id, user_agent: CHROME, ip_address: "203.0.113.7") }

    assert first.persisted?
    assert_equal first.id, again.id
    assert_equal 1, within { Device.count }
  end

  test "a device names itself from its user agent until someone names it" do
    device = within { Device.identify(nil, user_agent: CHROME) }

    assert_equal "Chrome on Mac", device.label
    assert_equal "desktop", device.category
    assert device.known?

    within { device.update!(name: "The kitchen laptop") }

    assert_equal "The kitchen laptop", device.label
  end

  test "a device with no readable user agent is labelled, not rejected" do
    device = within { Device.identify(nil, user_agent: "") }

    assert device.persisted?
    assert_equal Device::UNKNOWN, device.label
    assert_equal "unknown", device.category
    assert_not device.known?
  end

  test "the same public id in another tenant is another device" do
    mine = within { Device.identify(nil, user_agent: CHROME) }
    theirs = within(@other) { Device.identify(mine.public_id, user_agent: CHROME) }

    assert_not_equal mine.id, theirs.id
    assert_equal 1, within { Device.count }
    assert_equal 1, within(@other) { Device.count }
  end

  test "a session resumes only while the device still carries the version it started with" do
    within do
      device = Device.identify(nil, user_agent: CHROME)
      session = Session.start!(actor: @actor, device: device)

      assert_equal session.id, Session.resume(session.secret)&.id

      device.rotate!

      assert_nil Session.resume(session.secret)
    end
  end

  test "a blocked device resumes nothing, even on a session it started" do
    within do
      device = Device.identify(nil, user_agent: CHROME)
      session = Session.start!(actor: @actor, device: device)

      device.update_columns(blocked_at: Time.current)

      assert_nil Session.resume(session.secret)
    end
  end

  test "signing a device out revokes its sessions, its tokens, and what it was trusted for" do
    within do
      device = Device.identify(nil, user_agent: CHROME)
      session = Session.start!(actor: @actor, device: device)
      client = Client.create!(
        name: "Probe", client_id: SecureRandom.uuid,
        redirect_uris: [ "https://probe.example.com/cb" ], token_endpoint_auth_method: "none"
      )
      token = RefreshToken.mint!(actor: @actor, client: client, device: device)

      DeviceFactor.remember!(device: device, actor: @actor)

      assert DeviceFactor.satisfied?(device: device, actor: @actor)

      device.sign_out!

      assert session.reload.revoked_at.present?
      assert token.reload.consumed?
      assert_not DeviceFactor.satisfied?(device: device, actor: @actor)
    end
  end

  test "blocking signs the device out too" do
    within do
      device = Device.identify(nil, user_agent: CHROME)
      session = Session.start!(actor: @actor, device: device)

      device.block!

      assert device.blocked?
      assert session.reload.revoked_at.present?
    end
  end

  test "a remembered factor lapses when it expires" do
    within do
      device = Device.identify(nil, user_agent: CHROME)

      DeviceFactor.remember!(device: device, actor: @actor, expiry: 1.hour)

      assert DeviceFactor.satisfied?(device: device, actor: @actor)

      travel 2.hours do
        assert_not DeviceFactor.satisfied?(device: device, actor: @actor)
      end
    end
  end

  test "changing a password stops every device from skipping the second factor" do
    within do
      device = Device.identify(nil, user_agent: CHROME)

      DeviceFactor.remember!(device: device, actor: @actor)

      @actor.sign_out_everywhere!

      assert_not DeviceFactor.satisfied?(device: device, actor: @actor)
    end
  end

  test "a device only belongs to the actors that signed in from it" do
    within do
      device = Device.identify(nil, user_agent: CHROME)
      stranger = Actor.create!(nickname: "stranger", password: "password")

      Session.start!(actor: @actor, device: device)

      assert_includes @actor.devices, device
      assert_not_includes stranger.devices, device
    end
  end
end
