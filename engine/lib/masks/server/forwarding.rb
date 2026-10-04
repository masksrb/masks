module Masks
  module Server
    class Forwarding
      HEADERS = %w[HTTP_X_FORWARDED_FOR HTTP_X_FORWARDED_HOST HTTP_CLIENT_IP HTTP_FORWARDED].freeze

      def initialize(app, proxies)
        @app = app
        @proxies = proxies
      end

      def call(env)
        HEADERS.each { |header| env.delete(header) } unless trusted?(env["REMOTE_ADDR"])

        @app.call(env)
      end

      private

        def trusted?(address)
          peer = IPAddr.new(address.to_s.split("%").first)
          peer = peer.native if peer.ipv4_mapped?

          @proxies.any? { |proxy| proxy.include?(peer) }
        rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
          false
        end
    end
  end
end
