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

            organization = Masks::Server::Organization.transaction do
              save!(Masks::Server::Organization.new(key: key, name: name, roles: roles)).tap do |created|
                created.memberships.create!(actor: viewer, role: Masks::Server::Organization::OWNER, invited_by: viewer, pending: false)
              end
            end

            audit!(Masks::Server::Event::ORGANIZATION_CREATED, organization: organization.key)
            Masks::Server::Event.record!(Masks::Server::Event::MEMBERSHIP_ADDED, actor: viewer, by: viewer,
                                                                                 organization: organization,
                                                                                 role: Masks::Server::Organization::OWNER)

            { organization: organization }
          end
        end
      end
    end
  end
end
