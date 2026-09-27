module Masks
  module Server
    module Manage
      module Mutations
        class ArchiveOrganization < OrganizationMutation
          requires :security

          argument :key, ID

          field :organization, Types::OrganizationType, null: false

          def resolve(key:)
            organization = organization!(key)

            refuse!("#{organization.name} is already archived") if organization.archived?

            organization.archive!

            audit!(Masks::Server::Event::ORGANIZATION_ARCHIVED, organization: organization.key)

            { organization: organization }
          end
        end
      end
    end
  end
end
