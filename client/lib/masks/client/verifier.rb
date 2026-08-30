module Masks
  module Client
    class Verifier
      ALGORITHMS = %w[RS256 ES256].freeze

      attr_reader :issuer, :audience

      def initialize(issuer, audience:, algorithms: ALGORITHMS)
        @issuer = Issuer.resolve(issuer)
        @audience = Array(audience)
        @algorithms = algorithms
      end

      def verify(token, required: %w[iss sub exp])
        JWT.decode(
          token, nil, true,
          algorithms: @algorithms,
          jwks: keys,
          iss: issuer.url, verify_iss: true,
          aud: audience, verify_aud: true,
          verify_expiration: true,
          required_claims: required
        ).first
      rescue JWT::DecodeError => e
        raise InvalidToken, e.message
      end

      def tenant(token)
        verify(token)["tenant"]
      end

      private

        def keys
          ->(options) do
            issuer.refresh! if options[:invalidate]
            issuer.jwks
          end
        end
    end
  end
end
