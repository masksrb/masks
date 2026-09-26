module Masks
  module Server
    class PasswordReset < Token
      include MailedLink

      path "reset"

      def self.lifetime
        ::Rails.configuration.masks.password_reset_lifetime
      end

      def self.settle!(secret, password)
        claimed = claim(secret)
        return nil if claimed.nil?

        actor = claimed.actor

        transaction do
          actor.reset_password!(password, verifying_email: claimed.delivered?)
          CodeFactors.disable!(actor, "email", by: nil) if claimed.delivered?
        end

        actor
      end
    end
  end
end
