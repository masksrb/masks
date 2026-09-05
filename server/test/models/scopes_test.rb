require "test_helper"

class ScopesTest < ActiveSupport::TestCase
  test "a plain scope covers only itself" do
    available = %w[uris:catalog:read]

    assert Scopes.covered?(available, "uris:catalog:read")
    assert_not Scopes.covered?(available, "uris:catalog:write")
  end

  test "a trailing colon covers everything beneath it" do
    available = %w[uris:]

    assert Scopes.covered?(available, "uris:catalog:read")
    assert Scopes.covered?(available, "uris:settings:admin")
    assert_not Scopes.covered?(available, "masks:manage")
  end

  test "a prefix does not cover itself, only what is under it" do
    assert_not Scopes.covered?(%w[uris:], "uris:")
  end

  test "a prefix does not leak across a neighbouring name" do
    assert_not Scopes.covered?(%w[uris:], "urisomething:read")
  end

  test "refused names what a prefix does not reach" do
    refused = Scopes.refused(%w[uris: openid], %w[openid uris:catalog:read masks:manage])

    assert_equal %w[masks:manage], refused
  end

  test "granted keeps the scopes asked for rather than the prefix" do
    granted = Scopes.granted(%w[uris:catalog:read uris:settings:write], %w[uris:])

    assert_equal %w[uris:catalog:read uris:settings:write], granted
  end

  test "covers? answers for a prefix as it does for a list" do
    assert Scopes.covers?(%w[uris:], %w[uris:catalog:read uris:resources:command])
    assert_not Scopes.covers?(%w[uris:], %w[uris:catalog:read masks:manage])
  end

  test "a dynamically registered client may not claim a prefix" do
    error = assert_raises(Client::ScopesUnavailable) do
      Client.bounded(%w[uris:])
    end

    assert_match(/uris:/, error.message)
    assert_match(/approved client/, error.message)
  end
end
