module Masks
  module Server
    module Manage
      module Mutations
        class CheckDomain < DomainMutation
          requires :security

          description "Looks up a claim's TXT record now, instead of waiting for the hourly check."

          argument :domain, String

          field :domain_claim, Types::DomainClaimType, null: false
          field :found, Boolean, null: false

          def resolve(domain:)
            claim = claim!(domain)
            was = claim.verified?
            found = claim.check!

            audit!(Masks::Server::Event::DOMAIN_VERIFIED, domain: claim.domain) if claim.verified? && !was

            { domain_claim: claim, found: found }
          rescue Masks::Server::DomainClaim::Taken => e
            refuse!(e.message)
          end
        end
      end
    end
  end
end
