require "test_helper"

class LoginEnumerationTest < ActiveSupport::TestCase
  setup do
    @actor = create_actor
    @client = create_client
  end

  def attempt(identifier, password)
    store = {}

    within do
      Login.new(store: store, client: @client, event: "identify",
                updates: { identifier: identifier }).update
      Login.new(store: store, client: @client, event: "password",
                updates: { password: password }).update
    end
  end

  def elapsed(identifier, password)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    attempt(identifier, password)
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  test "a missing account is indistinguishable from a wrong password" do
    missing = attempt("no-such-account", "wrong")
    wrong = attempt("owner", "wrong")

    assert_equal wrong.prompt, missing.prompt
    assert_equal wrong.warnings, missing.warnings
    assert_nil missing.actor
    assert_nil wrong.actor
  end

  test "the identifier step reveals nothing about whether an account exists" do
    known = within do
      Login.new(store: {}, client: @client, event: "identify",
                updates: { identifier: "owner" }).update
    end

    unknown = within do
      Login.new(store: {}, client: @client, event: "identify",
                updates: { identifier: "no-such-account" }).update
    end

    assert_equal known.prompt, unknown.prompt
    assert_equal known.warnings, unknown.warnings
    assert_nil known.actor, "the identifier step must not resolve an actor"
  end

  test "a missing account still costs a password comparison" do
    baseline = [ elapsed("owner", "wrong"), elapsed("owner", "wrong") ].min
    missing = [ elapsed("no-such-account", "wrong"), elapsed("no-such-account", "wrong") ].min

    assert_operator missing, :>, baseline / 3,
                    "a missing account returned far faster than a wrong password, " \
                    "which makes sign-in an enumeration oracle"
  end
end
