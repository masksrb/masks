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
                audit!(Masks::Server::Event::ORGANIZATION_CREATED, organization: created.key)
                Masks::Server::Members.enroll!(created, viewer, role: Masks::Server::Organization::OWNER, by: viewer)
              end
            end

            { organization: organization }
          rescue Masks::Server::Members::Refused => e
            refuse!(e.message)
          end
        end
      end
    end
  end
end
