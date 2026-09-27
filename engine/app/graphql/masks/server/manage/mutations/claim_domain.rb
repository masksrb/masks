module Masks
  module Server
    module Manage
      module Mutations
        class ClaimDomain < DomainMutation
          requires :security

          description "Starts claiming a domain. Publish the TXT record it returns, then check it."

          argument :domain, String
          argument :provider, ID, required: false, description: "The provider to send people with an address here to."

          field :domain_claim, Types::DomainClaimType, null: false

          def resolve(domain:, provider: nil)
            claim = save!(Masks::Server::DomainClaim.new(domain: domain, provider: signing_provider!(provider)))

            audit!(Masks::Server::Event::DOMAIN_CLAIMED, domain: claim.domain, provider: claim.provider&.key)

            { domain_claim: claim }
          end
        end
      end
    end
  end
end
