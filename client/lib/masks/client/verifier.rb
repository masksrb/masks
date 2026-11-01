module Masks
  module Client
    class Verifier
      ALGORITHMS = %w[RS256 ES256].freeze
      ACCESS_TOKEN = "at+jwt".freeze
      LOGOUT_TOKEN = "logout+jwt".freeze
      ID_TOKEN = [ "jwt", nil ].freeze
      AUTH_TIME_LEEWAY = 30

      def self.recent!(claims, max_age)
        return claims if max_age.nil?

        signed_in_at = claims["auth_time"]
        allowed = signed_in_at.is_a?(Numeric) && signed_in_at + max_age.to_i + AUTH_TIME_LEEWAY >= Time.now.to_i

        raise InvalidToken, Masks::Client.saying("too_old") unless allowed

        claims
      end

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
      rescue JWT::ExpiredSignature
        raise InvalidToken, Masks::Client.saying("expired")
      rescue JWT::InvalidIssuerError
        raise InvalidToken, Masks::Client.saying("other_issuer")
      rescue JWT::InvalidAudError
        raise InvalidToken, Masks::Client.saying("other_audience")
      rescue JWT::MissingRequiredClaim
        raise InvalidToken, Masks::Client.saying("missing_claims", "a claim it needs")
      rescue JWT::DecodeError
        raise InvalidToken, Masks::Client.saying("not_signed_by", issuer.url)
      end

      private

        def typed!(held, accepted)
          named = held&.to_s&.downcase&.delete_prefix("application/")

          return if accepted.include?(named)

          raise InvalidToken, Masks::Client.saying("wrong_type", held, accepted.compact.join(" or "))
        end

        def keys
          ->(options) { options[:invalidate] ? issuer.keys! : issuer.jwks }
        end
    end
  end
end
