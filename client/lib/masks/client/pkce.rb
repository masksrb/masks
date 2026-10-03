module Masks
  module Client
    class Pkce
      METHOD = "S256".freeze

      attr_reader :verifier

      def self.generate
        new(SecureRandom.urlsafe_base64(64))
      end

      def initialize(verifier)
        @verifier = verifier
      end

      def challenge
        Proof.digest(verifier)
      end

      def method
        METHOD
      end
    end
  end
end
