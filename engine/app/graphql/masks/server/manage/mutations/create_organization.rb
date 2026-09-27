module Masks
  module Server
    module Manage
      module Mutations
        class CreateOrganization < OrganizationMutation
          requires :security

          argument :key, ID
          argument :name, String
          argument :roles, [ String ], required: false, description: "Roles beyond owner and member."

          field :organization, Types::OrganizationType, null: false

          def resolve(key:, name:, roles: [])
            refuse!("an organization is already keyed #{key}") if Masks::Server::Organization.exists?(key: key)

            organization = save!(Masks::Server::Organization.new(key: key, name: name, roles: roles))

            audit!(Masks::Server::Event::ORGANIZATION_CREATED, organization: organization.key)

            { organization: organization }
          end
        end
      end
    end
  end
end
