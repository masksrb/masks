require "test_helper"

class ScopesTest < ActiveSupport::TestCase
  test "a plain scope covers only itself" do
    available = %w[things:catalog:read]

    assert Scopes.covered?(available, "things:catalog:read")
    assert_not Scopes.covered?(available, "things:catalog:write")
  end

  test "a trailing colon covers everything beneath it" do
    available = %w[things:]

    assert Scopes.covered?(available, "things:catalog:read")
    assert Scopes.covered?(available, "things:settings:admin")
    assert_not Scopes.covered?(available, "masks:manage")
  end

  test "a prefix does not cover itself, only what is under it" do
    assert_not Scopes.covered?(%w[things:], "things:")
  end

  test "a prefix does not leak across a neighbouring name" do
    assert_not Scopes.covered?(%w[things:], "thingsomething:read")
  end

  test "refused names what a prefix does not reach" do
    refused = Scopes.refused(%w[things: openid], %w[openid things:catalog:read masks:manage])

    assert_equal %w[masks:manage], refused
  end

  test "granted keeps the scopes asked for rather than the prefix" do
    granted = Scopes.granted(%w[things:catalog:read things:settings:write], %w[things:])

    assert_equal %w[things:catalog:read things:settings:write], granted
  end

  test "covers? answers for a prefix as it does for a list" do
    assert Scopes.covers?(%w[things:], %w[things:catalog:read things:resources:command])
    assert_not Scopes.covers?(%w[things:], %w[things:catalog:read masks:manage])
  end

  test "a dynamically registered client may not claim a prefix" do
    error = assert_raises(Client::ScopesUnavailable) do
      Client.bounded(%w[things:])
    end

    assert_match(/things:/, error.message)
    assert_match(/approved client/, error.message)
  end
end
