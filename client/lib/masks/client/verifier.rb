module Masks
  module Client
    class Verifier
      ALGORITHMS = %w[RS256 ES256].freeze
      ACCESS_TOKEN = "at+jwt".freeze
      LOGOUT_TOKEN = "logout+jwt".freeze
      ID_TOKEN = [ "jwt", nil ].freeze

      attr_reader :issuer, :audience

      def initialize(issuer, audience:, algorithms: ALGORITHMS)
        @issuer = Issuer.resolve(issuer)
        @audience = Array(audience)
        @algorithms = algorithms
      end

      def verify(token, required: %w[iss sub exp], typ: ID_TOKEN)
        claims, header = JWT.decode(
          token, nil, true,
          algorithms: @algorithms,
          jwks: keys,
          iss: issuer.url, verify_iss: true,
          aud: audience, verify_aud: true,
          verify_expiration: true,
          required_claims: required
        )

        typed!(header["typ"], Array(typ))

        claims
      rescue JWT::DecodeError => e
        raise InvalidToken, e.message
      end

      def tenant(token)
        verify(token)["tenant"]
      end

      private

        def typed!(held, accepted)
          named = held&.to_s&.downcase&.delete_prefix("application/")

          return if accepted.include?(named)

          raise InvalidToken, "that token is typed #{held.inspect}, not #{accepted.compact.join(' or ')}"
        end

        def keys
          ->(options) do
            issuer.refresh! if options[:invalidate]
            issuer.jwks
          end
        end
    end
  end
end
