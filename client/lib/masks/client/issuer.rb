module Masks
  module Client
    class Issuer
      DISCOVERY_PATH = "/.well-known/openid-configuration".freeze
      TTL = 300

      def self.normalize(url)
        url.to_s.chomp("/")
      end

      def self.resolve(issuer, ttl: TTL)
        return issuer if issuer.is_a?(self)

        Masks::Client.registry[issuer, ttl: ttl]
      end

      attr_reader :url

      def initialize(url, ttl: TTL)
        @url = self.class.normalize(url)
        @ttl = ttl
        @cache = {}
        @lock = Mutex.new
      end

      def discovery
        fetch(:discovery) do
          document = HTTP.get("#{url}#{DISCOVERY_PATH}")
          named = self.class.normalize(document["issuer"])

          unless named == url
            raise Rejected.new(
              "invalid_issuer",
              "#{url} publishes a document naming #{document['issuer'].inspect}"
            )
          end

          document
        end
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
        @lock.synchronize { @cache = {} }
        self
      end

      private

        def fetch(key)
          cached = @lock.synchronize { @cache[key] }
          return cached[:value] if fresh?(cached)

          value = yield

          @lock.synchronize { @cache[key] = { value: value, at: Time.now.to_i } }
          value
        end

        def fresh?(entry)
          entry && entry[:at] + @ttl > Time.now.to_i
        end
    end
  end
end
