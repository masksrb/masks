module Masks
  module Client
    class Issuer
      DISCOVERY_PATH = "/.well-known/openid-configuration".freeze
      TTL = 300

      attr_reader :url

      def initialize(url, ttl: TTL)
        @url = url.to_s.chomp("/")
        @ttl = ttl
        @cache = {}
      end

      def discovery
        fetch(:discovery) { HTTP.get("#{url}#{DISCOVERY_PATH}") }
      end

      def jwks
        fetch(:jwks) { HTTP.get(endpoint("jwks_uri")) }
      end

      def tenant
        discovery["tenant"]
      end

      def endpoint(name)
        discovery.fetch(name) { raise Rejected.new("invalid_issuer", "#{url} publishes no #{name}") }
      end

      def refresh!
        @cache = {}
        self
      end

      private

        def fetch(key)
          entry = @cache[key]
          return entry[:value] if entry && entry[:at] + @ttl > Time.now.to_i

          value = yield
          @cache[key] = { value: value, at: Time.now.to_i }
          value
        end
    end
  end
end
