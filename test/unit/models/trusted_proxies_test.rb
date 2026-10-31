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

      def through(proxies, peer:, status: 200, location: nil, **headers)
        env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => peer, **headers)
        seen = nil
        app = ->(held) { seen = held; [ status, location ? { "location" => location } : {}, [] ] }

        Forwarding.new(app, proxies).call(env)

        seen
      end

      def noted(kind)
        (::Rails.cache.read(Health::PROXY_KEY) || {}).fetch(kind, {}).keys
      end

      def logged
        io = StringIO.new
        held = ::Rails.logger
        ::Rails.logger = ActiveSupport::Logger.new(io)

        yield

        io.string
      ensure
        ::Rails.logger = held
      end

      test "forwarded headers from an address nobody named are noted for the health panel and the log" do
        Health.forget_proxy!

        output = logged do
          through(Configuration.trusted_proxies(nil), peer: "203.0.113.5", "HTTP_X_FORWARDED_FOR" => "198.51.100.7")
        end

        assert_equal [ "203.0.113.5" ], noted("untrusted")
        assert_includes output, "proxy: forwarded headers arrived from 203.0.113.5"
        assert_empty noted("plain")
      end

      test "a visitor with no forwarded headers is not a proxy, and is not noted" do
        Health.forget_proxy!

        through(Configuration.trusted_proxies(nil), peer: "203.0.113.6")

        assert_empty noted("untrusted")
      end

      test "an untrusted visitor cannot claim a scheme either" do
        seen = through(Configuration.trusted_proxies(nil), peer: "203.0.113.5", "HTTP_X_FORWARDED_PROTO" => "https")

        assert_nil seen["HTTP_X_FORWARDED_PROTO"]
      end

      test "a trusted proxy that forwards plain http is noted, unless the answer sends the browser to https" do
        Health.forget_proxy!
        proxies = Configuration.trusted_proxies(nil)

        through(proxies, peer: "10.0.0.2", "HTTP_X_FORWARDED_PROTO" => "https")
        assert_empty noted("plain")

        through(proxies, peer: "10.0.0.3", status: 301, location: "https://auth.example/", "HTTP_X_FORWARDED_PROTO" => "http")
        assert_empty noted("plain")

        output = logged { through(proxies, peer: "10.0.0.4", "HTTP_X_FORWARDED_PROTO" => "http") }
        assert_equal [ "10.0.0.4" ], noted("plain")
        assert_includes output, "proxy: 10.0.0.4 forwards requests as plain http"
      end

      test "a proxy that is not an address stops the server from booting" do
        error = assert_raises(RuntimeError) { Configuration.trusted_proxies("cloudflare") }

        assert_match "MASKS_TRUSTED_PROXIES", error.message
      end
    end
  end
end
