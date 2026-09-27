module Masks
  module Server
    module Manage
      module Mutations
        class RestoreOrganization < OrganizationMutation
          requires :security

          argument :key, ID

          field :organization, Types::OrganizationType, null: false

          def resolve(key:)
            organization = organization!(key)

            refuse!("#{organization.name} is not archived") unless organization.archived?

            organization.update!(archived_at: nil)

            audit!(Masks::Server::Event::ORGANIZATION_UPDATED, organization: organization.key, changed: [ "restored" ])

            { organization: organization }
          end
        end
      end
    end
  end
end
