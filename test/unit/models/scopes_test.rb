module Masks
  module Server
    require "test_helper"

    class ScopesTest < ActiveSupport::TestCase
      test "a plain scope covers only itself" do
        available = %w[xixo:catalog:read]

        assert Scopes.covered?(available, "xixo:catalog:read")
        assert_not Scopes.covered?(available, "xixo:catalog:write")
      end

      test "a trailing colon covers everything beneath it" do
        available = %w[xixo:]

        assert Scopes.covered?(available, "xixo:catalog:read")
        assert Scopes.covered?(available, "xixo:settings:admin")
        assert_not Scopes.covered?(available, "masks:manage")
      end

      test "a prefix does not cover itself, only what is under it" do
        assert_not Scopes.covered?(%w[xixo:], "xixo:")
      end

      test "a prefix does not leak across a neighbouring name" do
        assert_not Scopes.covered?(%w[xixo:], "xixomething:read")
      end

      test "refused names what a prefix does not reach" do
        refused = Scopes.refused(%w[xixo: openid], %w[openid xixo:catalog:read masks:manage])

        assert_equal %w[masks:manage], refused
      end

      test "granted keeps the scopes asked for rather than the prefix" do
        granted = Scopes.granted(%w[xixo:catalog:read xixo:settings:write], %w[xixo:])

        assert_equal %w[xixo:catalog:read xixo:settings:write], granted
      end

      test "covers? answers for a prefix as it does for a list" do
        assert Scopes.covers?(%w[xixo:], %w[xixo:catalog:read xixo:resources:command])
        assert_not Scopes.covers?(%w[xixo:], %w[xixo:catalog:read masks:manage])
      end

      test "a dynamically registered client may not claim a prefix" do
        error = assert_raises(Client::ScopesUnavailable) do
          Client.bounded(%w[xixo:])
        end

        assert_match(/xixo:/, error.message)
        assert_match(/approved client/, error.message)
      end
    end
  end
end
