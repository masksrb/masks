module Masks
  module Server
    module LockedOut
      class << self
        def recover!(named = ::Rails.configuration.masks.recover)
          return [] if named.blank?

          subdomain, identifier = named.include?("/") ? named.split("/", 2) : [ nil, named ]
          tenants = subdomain ? Tenant.active.where(subdomain: subdomain) : Tenant.active

          tenants.filter_map { |tenant| Tenant.switch(tenant) { recover_in(tenant, identifier) } }
        end

        private

          def recover_in(tenant, identifier)
            actor = Actor.locate(identifier)
            return if actor.nil?

            HelpRequests.reset!(actor, by: nil)
            reset = PasswordReset.open!(actor: actor)
            Event.record!(Event::PASSWORD_RESET_REQUESTED, actor: actor, by: nil, from: "MASKS_RECOVER")

            "#{tenant.subdomain}: #{actor.identifier} has no second factors now and every session is signed out. " \
              "This link sets a new password once: #{reset.url(tenant.public_origin.to_s)}"
          end
      end
    end
  end
end
