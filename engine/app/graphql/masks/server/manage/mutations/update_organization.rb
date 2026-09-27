module Masks
  module Server
    module Manage
      module Mutations
        class UpdateOrganization < OrganizationMutation
          requires :security

          argument :key, ID
          argument :name, String, required: false
          argument :roles, [ String ], required: false, description: "Roles beyond owner and member. A role a member still holds cannot be removed."

          field :organization, Types::OrganizationType, null: false

          def resolve(key:, name: nil, roles: nil)
            organization = live!(organization!(key))

            organization.name = name unless name.nil?

            unless roles.nil?
              organization.roles = roles
              held = organization.memberships.where.not(role: organization.role_list).distinct.pluck(:role)
              refuse!("members still hold #{held.join(', ')}") if held.any?
            end

            save!(organization)

            audit!(Masks::Server::Event::ORGANIZATION_UPDATED, organization: organization.key,
                                                              changed: [ name && "name", roles && "roles" ].compact)

            { organization: organization }
          end
        end
      end
    end
  end
end
