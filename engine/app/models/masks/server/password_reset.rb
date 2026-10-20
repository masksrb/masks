module Masks
  module Server
    class PasswordReset < Token
      include MailedLink

      path "reset"

      def self.lifetime(tenant = Current.tenant)
        Tenant.link_lifetime(:password_reset_lifetime, tenant)
      end

      def self.settle!(secret, password)
        claimed = claim(secret)
        return nil if claimed.nil?

        actor = claimed.actor
        verifying = claimed.delivered? && claimed.addressed?
        claiming = verifying && actor.email_unconfirmed?

        transaction do
          actor.reset_password!(password, verifying_email: verifying)
          CodeFactors.disable!(actor, "email", by: nil) if claimed.delivered?
          actor.forget_unproven_ways_in! if claiming
        end

        actor
      end
    end
  end
end
