module Masks
  module Client
    class Tokens
      EXCHANGE = "urn:ietf:params:oauth:grant-type:token-exchange".freeze
      ACCESS_TOKEN = "urn:ietf:params:oauth:token-type:access_token".freeze

      attr_reader :access_token, :id_token, :refresh_token, :token_type, :scope, :expires_in, :obtained_at

      def self.granted(body)
        token = new(body)

        if token.access_token.to_s.empty?
          raise Rejected.new(
            body["error"] || "invalid_token_response",
            body["error_description"] || "the token endpoint answered without an access_token"
          )
        end

        token
      end

      def initialize(body)
        @access_token = body["access_token"]
        @id_token = body["id_token"]
        @refresh_token = body["refresh_token"]
        @token_type = body["token_type"] || "Bearer"
        @scope = body["scope"].to_s
        @expires_in = body["expires_in"].to_i
        @obtained_at = Time.now.to_i
      end

      def expires_at
        obtained_at + expires_in
      end

      def expired?(leeway: 30)
        Time.now.to_i + leeway >= expires_at
      end

      def scopes
        scope.split(/\s+/).reject(&:empty?)
      end

      def authorization
        "#{token_type} #{access_token}"
      end

      def to_h
        {
          "access_token" => access_token,
          "id_token" => id_token,
          "refresh_token" => refresh_token,
          "token_type" => token_type,
          "scope" => scope,
          "expires_in" => expires_in,
          "obtained_at" => obtained_at
        }.compact
      end

      def self.from_h(data)
        return nil if data.nil? || data.empty?

        tokens = allocate
        tokens.send(:initialize, data)
        tokens.instance_variable_set(:@obtained_at, data["obtained_at"] || Time.now.to_i)
        tokens
      end
    end
  end
end
