module Masks
  module Server
    module ProofOfWork
      PURPOSE = "proof-of-work".freeze
      LIFETIME = 10.minutes
      HARDEST = 28
      COUNTER = /\A\d{1,16}\z/

      module_function

      def issue(bits:, bound_to:)
        nonce = SecureRandom.hex(16)
        token = verifier.generate({ "nonce" => nonce, "bits" => bits, "bound" => bound_to.to_s },
                                  expires_in: LIFETIME)

        { "token" => token, "nonce" => nonce, "bits" => bits }
      end

      def verify(token, counter, bits:, bound_to:)
        held = verifier.verified(token.to_s)

        return false unless held.is_a?(Hash) && held["nonce"].is_a?(String)
        return false unless ActiveSupport::SecurityUtils.secure_compare(held["bound"].to_s, bound_to.to_s)
        return false if held["bits"].to_i < bits
        return false unless solves?(held["nonce"], counter, held["bits"].to_i)

        Replay.first?(PURPOSE, held["nonce"], expires_in: LIFETIME)
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        false
      end

      def solves?(nonce, counter, bits)
        return false unless counter.to_s.match?(COUNTER)

        Digest::SHA256.digest("#{nonce}#{counter}").unpack1("B*").start_with?("0" * bits)
      end

      def verifier
        Server.message_verifier(PURPOSE)
      end
    end
  end
end
