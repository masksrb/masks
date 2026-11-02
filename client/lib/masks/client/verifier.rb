module Masks
  module Client
    class Verifier
      ALGORITHMS = %w[RS256 ES256].freeze
      ACCESS_TOKEN = "at+jwt".freeze
      LOGOUT_TOKEN = "logout+jwt".freeze
      ID_TOKEN = [ "jwt", nil ].freeze
      LEEWAY = 30
      AUTH_TIME_LEEWAY = 30

      def self.recent!(claims, max_age)
        return claims if max_age.nil?

        signed_in_at = claims["auth_time"]
        allowed = signed_in_at.is_a?(Numeric) && signed_in_at + max_age.to_i + AUTH_TIME_LEEWAY >= Time.now.to_i

        raise InvalidToken.of("too_old") unless allowed

        claims
      end

      def self.header(token)
        segments = token.to_s.split(".", -1)

        raise InvalidToken.of("not_a_jwt") unless segments.size == 3

        held = JSON.parse(Base64.urlsafe_decode64(segments.first))

        raise InvalidToken.of("not_a_jwt") unless held.is_a?(Hash)

        held
      rescue ArgumentError, JSON::ParserError
        raise InvalidToken.of("not_a_jwt")
      end

      attr_reader :issuer, :audience

      def initialize(issuer, audience:, algorithms: ALGORITHMS)
        @issuer = Issuer.resolve(issuer)
        @audience = Array(audience)
        @algorithms = algorithms
      end

      def verify(token, required: %w[iss sub exp], typ: ID_TOKEN)
        header = self.class.header(token)
        algorithm = header["alg"].to_s

        raise InvalidToken.of("not_an_algorithm", algorithm) unless @algorithms.include?(algorithm)

        typed!(header["typ"], Array(typ))

        claims, = JWT.decode(
          token, key_for(header["kid"]), true,
          algorithms: [ algorithm ],
          iss: issuer.url, verify_iss: true,
          aud: audience, verify_aud: true,
          verify_expiration: true, exp_leeway: LEEWAY,
          verify_not_before: true, nbf_leeway: LEEWAY,
          verify_iat: false
        )

        Array(required).each { |name| raise InvalidToken.of("missing_claims", name) unless claims.key?(name) }

        issued = claims["iat"]

        raise InvalidToken.of("issued_in_future") if issued.is_a?(Numeric) && issued > Time.now.to_i + LEEWAY

        claims
      rescue JWT::ExpiredSignature
        raise InvalidToken.of("expired")
      rescue JWT::ImmatureSignature
        raise InvalidToken.of("not_valid_yet")
      rescue JWT::InvalidIssuerError
        raise InvalidToken.of("other_issuer")
      rescue JWT::InvalidAudError
        raise InvalidToken.of("other_audience")
      rescue JWT::DecodeError
        raise InvalidToken.of("not_signed_by", issuer.url)
      end

      private

        def typed!(held, accepted)
          named = held&.to_s&.downcase&.delete_prefix("application/")

          return if accepted.include?(named)

          raise InvalidToken.of("wrong_type", held.to_s.empty? ? "nothing" : held, accepted.compact.join(" or "))
        end

        def key_for(kid)
          found = published(issuer.jwks, kid) || published(issuer.keys!, kid)

          raise InvalidToken.of("no_key", issuer.url, kid.to_s) if found.nil?

          JWT::JWK.import(found).verify_key
        end

        def published(jwks, kid)
          keys = jwks.is_a?(Hash) ? Array(jwks["keys"]) : []

          keys.find { |key| key.is_a?(Hash) && key["kid"] == kid && key.fetch("use", "sig") == "sig" }
        end
    end
  end
end
