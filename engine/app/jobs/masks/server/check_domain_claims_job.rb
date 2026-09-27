module Masks
  module Server
    class CheckDomainClaimsJob < ApplicationJob
      queue_as :maintenance
      across_tenants!

      def perform
        Tenant.active.find_each do |tenant|
          Tenant.switch(tenant) { check }
        end
      end

      private

        def check
          DomainClaim.find_each do |claim|
            was = claim.verified?

            claim.check!

            Event.record!(Event::DOMAIN_VERIFIED, by: nil, domain: claim.domain) if claim.verified? && !was
            Event.record!(Event::DOMAIN_RELEASED, by: nil, domain: claim.domain, reason: "record gone") if was && !claim.verified?
          rescue DomainClaim::Taken => e
            ::Rails.logger.warn(e.message)
          end
        end
    end
  end
end
