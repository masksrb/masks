module Masks
  module Server
    module Manage
      module Mutations
        class SetMemberRole < OrganizationMutation
          requires :support

          argument :organization, ID
          argument :uuid, ID
          argument :role, String

          field :membership, Types::MembershipType, null: false

          def resolve(organization:, uuid:, role:)
            held = live!(organization!(organization))
            membership = member!(held, actor!(uuid))

            { membership: Masks::Server::Members.assign!(membership, role: role, by: viewer) }
          rescue Masks::Server::Members::Refused => e
            refuse!(e.message)
          end
        end
      end
    end
  end
end
