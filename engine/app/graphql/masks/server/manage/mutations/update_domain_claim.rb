module Masks
  module Server
    module Manage
      module Mutations
        class UpdateDomainClaim < DomainMutation
          requires :security

          argument :domain, String
          argument :provider, ID, required: false, description: "A provider's key, or null to stop sending people anywhere."

          field :domain_claim, Types::DomainClaimType, null: false

          def resolve(domain:, provider: nil)
            claim = claim!(domain)
            claim.provider = signing_provider!(provider)
            save!(claim)

            audit!(Masks::Server::Event::DOMAIN_CLAIMED, domain: claim.domain, provider: claim.provider&.key)

            { domain_claim: claim }
          end
        end
      end
    end
  end
end
