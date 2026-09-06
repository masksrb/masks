module Masks
  module Client
    class Logout
      EVENT = "http://schemas.openid.net/event/backchannel-logout".freeze
      ALGORITHMS = Verifier::ALGORITHMS
      LEEWAY = 60

      class << self
        def verify(token, issuer:, audience:, algorithms: ALGORITHMS)
          held = Verifier
            .new(issuer, audience: audience, algorithms: algorithms)
            .verify(token, required: %w[iss aud iat jti events])

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

      def validate!
        refuse!("logout token carries a nonce, so it is an id token") if claims.key?("nonce")
        refuse!("logout token names neither a subject nor a session") if subject.nil? && sid.nil?
        refuse!("logout token was issued in the future") if issued_at > Time.now.utc + LEEWAY

        held = claims["events"]

        refuse!("logout token has no events claim") unless held.is_a?(Hash)
        refuse!("logout token is not about a logout") unless held[EVENT].is_a?(Hash)

        self
      end

      private

        def refuse!(said)
          raise InvalidToken, said
        end
    end
  end
end
