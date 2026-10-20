module Masks
  module Server
    class Invitation < Token
      include MailedLink

      class Refused < StandardError; end

      path "invite"

      def self.lifetime(tenant = Current.tenant)
        Tenant.link_lifetime(:invitation_lifetime, tenant)
      end

      def self.open!(actor:, by: nil)
        raise Refused, "#{actor.identifier} has already accepted an invitation" if actor.activated?

        super
      end

      def self.accept!(secret, password)
        claimed = claim(secret)
        return nil if claimed.nil?

        claimed.actor.activate!(password, verifying_email: claimed.delivered? && claimed.addressed?)
        claimed.actor
      end
    end
  end
end
