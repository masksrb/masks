module Masks
  module Client
    # One issuer's discovery document and keys, fetched once and kept for an
    # hour. While masks cannot be reached, the last good copies are served, a
    # token signed with a key never seen raises Unreachable, and refetches back
    # off from 5 seconds to once a minute.
    class Issuer
      DISCOVERY_PATH = "/.well-known/openid-configuration".freeze
      LIFETIME = 3600
      FIRST_BACKOFF = 5
      LONGEST_BACKOFF = 60
      TTL = LIFETIME

      def self.normalize(url)
        url.to_s.chomp("/")
      end

      def self.resolve(issuer, ttl: TTL)
        return issuer if issuer.is_a?(self)

        Masks::Client.registry[issuer, ttl: ttl]
      end

      attr_reader :url, :nonces

      def initialize(url, ttl: TTL)
        @url = self.class.normalize(url)
        @ttl = ttl
        @cache = {}
        @lock = Mutex.new
        @nonces = Nonces.new
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

      def keys!
        fetch(:jwks, now: true) { HTTP.get(endpoint("jwks_uri")) }
      end

      def tenant
        discovery["tenant"]
      end

      def endpoint(name)
        discovery.fetch(name) { raise Rejected.new("invalid_issuer", "#{url} publishes no #{name}") }
      end

      def backchannel_logout?
        discovery["backchannel_logout_supported"] == true
      end

      def avatar_styles
        discovery["avatar_styles_supported"] || Claims::Avatars::STYLES
      end

      def avatar_url(subject, style: nil, size: nil)
        wanted = (style || Claims::Avatars::FALLBACK).to_s

        unless avatar_styles.include?(wanted)
          raise Rejected.new("invalid_style", "#{url} does not serve #{wanted} avatars")
        end

        query = size ? "?size=#{size.to_i}" : ""

        "#{endpoint('avatar_endpoint')}/#{subject}/#{wanted}#{query}"
      end

      def refresh!
        @lock.synchronize { @cache.each_value { |held| held[:at] = 0 } }
        self
      end

      private

        def fetch(key, now: false, &fetching)
          held = @lock.synchronize { @cache[key] ||= { backoff: FIRST_BACKOFF, retry_at: 0 } }
          clock = Time.now.to_i
          good = held.key?(:value)

          return held[:value] if good && !now && (held[:at] + @ttl > clock || clock < held[:retry_at])
          raise held[:failure] if clock < held[:retry_at]

          refetch(held, clock, keep: good && !now, &fetching)
        end

        def refetch(held, clock, keep:)
          value = yield

          @lock.synchronize do
            held.merge!(value: value, at: clock, failure: nil, retry_at: 0, backoff: FIRST_BACKOFF)
          end

          value
        rescue Masks::Client::Error => e
          @lock.synchronize do
            held[:failure] = e
            held[:retry_at] = clock + held[:backoff]
            held[:backoff] = [ held[:backoff] * 2, LONGEST_BACKOFF ].min
          end

          raise e unless keep

          held[:value]
        end
    end
  end
end
