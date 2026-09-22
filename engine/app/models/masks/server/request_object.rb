module Masks
  module Server
    class RequestObject
      class Refused < StandardError; end

      TYPE = "oauth-authz-req+jwt".freeze
      TYPES = [ TYPE, "application/#{TYPE}", "jwt", nil ].freeze
      SUBJECT = "that request object".freeze
      CARRIED = %w[
        response_type redirect_uri scope state nonce code_challenge code_challenge_method
        prompt max_age resource claims dpop_jkt
      ].freeze

      def self.unpack!(authorization, issuer:)
        new(authorization.request_object, client: authorization.client, client_id: authorization.client_id, issuer: issuer).authorization
      end

      def initialize(token, client:, client_id:, issuer:)
        @token = token.to_s
        @client = client
        @client_id = client_id.to_s
        @issuer = issuer
      end

      def authorization
        claims = verified

        Authorization.new(**claims.slice(*CARRIED).symbolize_keys, client_id: client_id, signed: true)
      end

      private

        attr_reader :token, :client, :client_id, :issuer

        def verified
          raise Refused, "client_id is required beside a request object" if client_id.blank?
          raise Refused, "no client is registered with that client_id" if client.nil?
          raise Refused, "this client has registered no keys to sign a request object with" unless client.keys?

          claims, header = keys.decode(token, subject: SUBJECT)

          typed!(header)
          named!(claims)
          keys.timely!(claims, subject: SUBJECT)
          recent!(claims)
          contained!(claims)
          keys.once!(claims, kind: "request-object", subject: SUBJECT) if claims["jti"].present?

          claims
        rescue ClientKeys::Refused => e
          raise Refused, e.message
        end

        def keys
          @keys ||= ClientKeys.new(client)
        end

        def typed!(header)
          held = header["typ"]&.to_s&.downcase

          raise Refused, "a request object is typed #{TYPE}, not #{header['typ']}" unless TYPES.include?(held)
        end

        def named!(claims)
          raise Refused, "a request object's iss must be the client that signed it" unless claims["iss"] == client.client_id
          raise Refused, "the client_id inside a request object must match the one beside it" unless claims["client_id"] == client_id

          unless Array(claims["aud"]).map { |one| one.to_s.chomp("/") }.include?(issuer.url)
            raise Refused, "a request object must be addressed to #{issuer.url}"
          end
        end

        def recent!(claims)
          return unless claims["nbf"].is_a?(Numeric) && claims["nbf"] < Time.current.to_i - ClientKeys::LONGEST.to_i

          raise Refused, "#{SUBJECT} was made more than #{ClientKeys::LONGEST.inspect} ago"
        end

        def contained!(claims)
          raise Refused, "a request object may not carry another request" if claims.key?("request") || claims.key?("request_uri")
        end
    end
  end
end
