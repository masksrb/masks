module Masks
  module Server
    module Manage
      module Mutations
        class ReleaseDomain < DomainMutation
          requires :security

          argument :domain, String

          field :domain, String, null: false

          def resolve(domain:)
            claim = claim!(domain)
            claim.destroy!

            audit!(Masks::Server::Event::DOMAIN_RELEASED, domain: claim.domain, reason: "released")

            { domain: claim.domain }
          end
        end
      end
    end
  end
end
