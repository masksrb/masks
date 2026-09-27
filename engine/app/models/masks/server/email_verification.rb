module Masks
  module Server
    class EmailVerification < Token
      include MailedLink

      path "verify"

      def self.lifetime
        ::Rails.configuration.masks.email_verification_lifetime
      end

      def self.settle!(secret)
        claimed = claim(secret)
        return nil if claimed.nil?
        return nil unless claimed.addressed?

        claimed.actor.update!(email_verified_at: Time.current)
        claimed.actor
      end
    end
  end
end
