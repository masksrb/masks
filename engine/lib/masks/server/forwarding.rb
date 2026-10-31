module Masks
  module Server
    class Forwarding
      HEADERS = %w[
        HTTP_X_FORWARDED_FOR HTTP_X_FORWARDED_HOST HTTP_CLIENT_IP HTTP_FORWARDED
        HTTP_X_FORWARDED_PROTO HTTP_X_FORWARDED_SCHEME HTTP_X_FORWARDED_SSL HTTP_X_FORWARDED_PORT
      ].freeze
      PROTO = "HTTP_X_FORWARDED_PROTO".freeze

      def initialize(app, proxies)
        @app = app
        @proxies = proxies
      end

      def call(env)
        address = env["REMOTE_ADDR"]
        trusted = trusted?(address)

        unless trusted
          Health.note_proxy!("untrusted", address) if HEADERS.any? { |header| env.key?(header) }
          HEADERS.each { |header| env.delete(header) }
        end

        plain = trusted && plain?(env)
        status, headers, body = @app.call(env)

        Health.note_proxy!("plain", address) if plain && !sent_to_https?(status, headers)

        [ status, headers, body ]
      end

      private

        def trusted?(address)
          peer = IPAddr.new(address.to_s.split("%").first)
          peer = peer.native if peer.ipv4_mapped?

          @proxies.any? { |proxy| proxy.include?(peer) }
        rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
          false
        end

        def plain?(env)
          env[PROTO].to_s.split(",").first.to_s.strip.casecmp?("http")
        end

        def sent_to_https?(status, headers)
          (300..399).cover?(status) && headers["location"].to_s.downcase.start_with?("https://")
        end
    end
  end
end
