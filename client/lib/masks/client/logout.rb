module Masks
  module Client
    class Logout
      EVENT = "http://schemas.openid.net/event/backchannel-logout".freeze
      ALGORITHMS = Verifier::ALGORITHMS
      REQUIRED = %w[iss aud iat exp jti].freeze
      LEEWAY = 60

      class << self
        def verify(token, issuer:, audience:, algorithms: ALGORITHMS)
          held = Verifier
            .new(issuer, audience: audience, algorithms: algorithms)
            .verify(token, required: REQUIRED, typ: Verifier::LOGOUT_TOKEN)

          new(held).validate!
        end
      end

      attr_reader :claims

      def initialize(claims)
        @claims = claims
      end

      def subject
        claims["sub"]
      end

      def sid
        claims["sid"]
      end

      def jti
        claims["jti"]
      end

      def issued_at
        Time.at(claims["iat"].to_i).utc
      end

      def expires_at
        Time.at(claims["exp"].to_i).utc
      end

      def validate!
        raise InvalidToken.of("logout_with_nonce") if claims.key?("nonce")
        raise InvalidToken.of("logout_names_nobody") if subject.to_s.empty? && sid.to_s.empty?
        raise InvalidToken.of("issued_in_future") if issued_at > Time.now.utc + LEEWAY

        held = claims["events"]

        raise InvalidToken.of("not_a_logout") unless held.is_a?(Hash) && held[EVENT].is_a?(Hash)

        self
      end
    end
  end
end
