module Masks
  module Rails
    # The default place a single-tenant app keeps what the handshake gives it,
    # so `config.store` has something to be before a consumer writes one. An
    # app with more than one issuer wants its own — `things` keeps these on
    # `tenants`, because a handshake is per tenant there.
    class Credentials
      KEYS = %w[client_id client_secret registration_access_token registration_client_uri].freeze

      attr_reader :path

      def initialize(path)
        @path = Pathname.new(path)
        @lock = Mutex.new
      end

      def read
        @lock.synchronize { held }
      end

      def write(registration)
        @lock.synchronize do
          @held = {
            "client_id" => registration.client_id,
            "client_secret" => registration.client_secret,
            "registration_access_token" => registration.access_token,
            "registration_client_uri" => registration.uri,
            "connected_at" => Time.now.utc.iso8601
          }.compact

          path.dirname.mkpath
          path.write(JSON.pretty_generate(@held))
          path.chmod(0o600)
          @held
        end
      end

      def clear!
        @lock.synchronize do
          @held = nil
          path.delete if path.exist?
        end
      end

      def connected?
        read["client_id"].present?
      end

      private

        def held
          return @held if defined?(@held) && @held

          @held = path.exist? ? JSON.parse(path.read) : {}
        rescue JSON::ParserError
          @held = {}
        end
    end
  end
end
