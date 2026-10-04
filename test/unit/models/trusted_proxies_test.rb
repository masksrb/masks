module Masks
  module Server
    require "test_helper"

    class TrustedProxiesTest < ActiveSupport::TestCase
      def seen(proxies, peer:, **headers)
        env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => peer, **headers)
        app = ->(held) { [ 200, {}, [ held["action_dispatch.remote_ip"].to_s, held["HTTP_X_FORWARDED_HOST"].to_s ] ] }

        Forwarding.new(ActionDispatch::RemoteIp.new(app, false, proxies), proxies).call(env).last
      end

      test "a proxy the operator names passes on the address of whoever it forwarded" do
        proxies = Configuration.trusted_proxies("203.0.113.0/24, 2001:db8::/32")

        assert_equal "198.51.100.7", seen(proxies, peer: "203.0.113.5", "HTTP_X_FORWARDED_FOR" => "198.51.100.7").first
        assert_equal "198.51.100.7", seen(proxies, peer: "2001:db8::1", "HTTP_X_FORWARDED_FOR" => "198.51.100.7").first
      end

      test "a visitor nobody named as a proxy is the address, whatever it claims to have forwarded" do
        proxies = Configuration.trusted_proxies(nil)

        address, host = seen(proxies, peer: "203.0.113.5",
                                      "HTTP_X_FORWARDED_FOR" => "198.51.100.7",
                                      "HTTP_CLIENT_IP" => "198.51.100.8",
                                      "HTTP_X_FORWARDED_HOST" => "other.example.com")

        assert_equal "203.0.113.5", address
        assert_empty host
      end

      test "the private ranges Rails trusts by default are still trusted" do
        proxies = Configuration.trusted_proxies("203.0.113.0/24")

        assert_equal "198.51.100.7", seen(proxies, peer: "10.0.0.2", "HTTP_X_FORWARDED_FOR" => "198.51.100.7").first
        assert_equal "198.51.100.7", seen(proxies, peer: "::ffff:10.0.0.2", "HTTP_X_FORWARDED_FOR" => "198.51.100.7").first
      end

      test "a proxy that is not an address stops the server from booting" do
        error = assert_raises(RuntimeError) { Configuration.trusted_proxies("cloudflare") }

        assert_match "MASKS_TRUSTED_PROXIES", error.message
      end
    end
  end
end
