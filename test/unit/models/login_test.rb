require "test_helper"

class LoginTest < ActiveSupport::TestCase
  setup do
    @actor = create_actor
    @client = create_client
    @store = {}
  end

  def step(event: nil, **updates)
    within do
      Login.new(store: @store, event: event, updates: updates).update
    end
  end

  test "starts by asking who you are" do
    assert_equal "identify", step.prompt
  end

  test "an identifier alone advances to the first factor" do
    login = step(event: "identify", identifier: "owner")

    assert_equal "first-factor", login.prompt
    assert_empty login.warnings
  end

  test "a blank identifier does not advance" do
    login = step(event: "identify", identifier: "  ")

    assert_equal "identify", login.prompt
    assert_includes login.warnings, "missing-identifier"
  end

  test "a wrong password warns without advancing" do
    step(event: "identify", identifier: "owner")
    login = step(event: "password", password: "wrong")

    assert_equal "first-factor", login.prompt
    assert_includes login.warnings, "invalid-credentials"
    assert_nil login.actor
  end

  test "a correct password settles when there is no second factor" do
    step(event: "identify", identifier: "owner")
    login = step(event: "password", password: "password")

    assert_equal "settled", login.prompt
    assert login.settled?
    assert_equal @actor, login.actor
  end

  test "a password event without an identifier cannot authenticate" do
    login = step(event: "password", password: "password")

    assert_equal "identify", login.prompt
    assert_includes login.warnings, "missing-identifier"
    assert_nil login.actor
  end

  test "a correct password stops at the second factor when otp is enabled" do
    enable_otp(@actor)

    step(event: "identify", identifier: "owner")
    login = step(event: "password", password: "password")

    assert_equal "second-factor", login.prompt
    assert_not login.settled?
  end

  test "a wrong code warns without settling" do
    enable_otp(@actor)

    step(event: "identify", identifier: "owner")
    step(event: "password", password: "password")
    login = step(event: "otp", code: "000000")

    assert_equal "second-factor", login.prompt
    assert_includes login.warnings, "invalid-code"
  end

  test "a valid code settles" do
    totp = enable_otp(@actor)

    step(event: "identify", identifier: "owner")
    step(event: "password", password: "password")
    login = step(event: "otp", code: totp.now)

    assert_equal "settled", login.prompt
    assert login.settled?
  end

  test "a code cannot skip the first factor" do
    totp = enable_otp(@actor)

    step(event: "identify", identifier: "owner")
    login = step(event: "otp", code: totp.now)

    assert_equal "first-factor", login.prompt
    assert_not login.touched?(:second_factor)
  end

  test "a code cannot stand in for an expired first factor" do
    totp = enable_otp(@actor)

    step(event: "identify", identifier: "owner")
    step(event: "password", password: "password")

    travel LoginStates::Password::EXPIRY + 1.minute do
      login = step(event: "otp", code: totp.now)

      assert_equal "first-factor", login.prompt
      assert_includes login.warnings, "missing-first-factor"
      assert_not login.touched?(:second_factor)
    end
  end

  test "starting over clears the identifier and the factors" do
    step(event: "identify", identifier: "owner")
    step(event: "password", password: "password")

    login = step(event: "start-over")

    assert_equal "identify", login.prompt
    assert_nil login.identifier
    assert_empty @store
  end

  test "email addresses identify as well as nicknames" do
    within { @actor.update!(email: "owner@example.test") }

    step(event: "identify", identifier: "owner@example.test")
    login = step(event: "password", password: "password")

    assert_equal "settled", login.prompt
  end

  test "an expired first factor drops back to it" do
    step(event: "identify", identifier: "owner")
    step(event: "password", password: "password")

    travel LoginStates::Password::EXPIRY + 1.minute do
      assert_equal "first-factor", step.prompt
    end
  end
end
