module Masks
  module Server
    class EmailVerification < Token
      include MailedLink

      path "verify"

      def self.lifetime(tenant = Current.tenant)
        Tenant.link_lifetime(:email_verification_lifetime, tenant)
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
