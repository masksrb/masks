module Masks
  module Server
    module Manage
      module Mutations
        class UpdateOrganization < OrganizationMutation
          requires :security

          argument :key, ID
          argument :name, String, required: false
          argument :roles, [ String ], required: false, description: "Roles beyond owner and member. A role a member still holds cannot be removed."
          argument :sign_in_policy, ID, required: false, description: "A sign-in policy's key, or an empty string to follow the app and the tenant."

          field :organization, Types::OrganizationType, null: false

          def resolve(key:, name: nil, roles: nil, sign_in_policy: nil)
            organization = live!(organization!(key))

            organization.name = name unless name.nil?
            organization.sign_in_policy = sign_in_policy.empty? ? nil : sign_in_policy!(sign_in_policy) unless sign_in_policy.nil?

            unless roles.nil?
              organization.roles = roles
              held = organization.memberships.where.not(role: organization.role_list).distinct.pluck(:role)
              refuse!("members still hold #{held.join(', ')}") if held.any?
            end

            save!(organization)

            audit!(Masks::Server::Event::ORGANIZATION_UPDATED, organization: organization.key,
                                                              changed: [ name && "name", roles && "roles", sign_in_policy && "sign_in_policy" ].compact)

            { organization: organization }
          end
        end
      end
    end
  end
end
