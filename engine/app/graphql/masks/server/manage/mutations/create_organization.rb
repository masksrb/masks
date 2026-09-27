module Masks
  module Server
    module Manage
      module Mutations
        class CreateOrganization < OrganizationMutation
          requires :security

          description "Creates an organization, owned by the person who creates it."

          argument :key, ID
          argument :name, String
          argument :roles, [ String ], required: false, description: "Roles beyond owner and member."

          field :organization, Types::OrganizationType, null: false

          def resolve(key:, name:, roles: [])
            refuse!("an organization is already keyed #{key}") if Masks::Server::Organization.exists?(key: key)

            organization = Masks::Server::Organization.new(key: key, name: name, roles: roles)
            organization.memberships.build(actor: viewer, role: Masks::Server::Organization::OWNER, invited_by: viewer)
            save!(organization)

            audit!(Masks::Server::Event::ORGANIZATION_CREATED, organization: organization.key)
            audit!(Masks::Server::Event::MEMBERSHIP_ADDED, actor: viewer, organization: organization,
                                                           role: Masks::Server::Organization::OWNER)

            { organization: organization }
          end
        end
      end
    end
  end
end
