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
            was = membership.role

            membership.role = role
            save!(membership)

            audit!(Masks::Server::Event::MEMBERSHIP_ROLE_CHANGED, actor: membership.actor,
                                                                 organization: held.key, was: was, now: role)

            { membership: membership }
          end
        end
      end
    end
  end
end
