module Masks
  module Server
    module Manage
      module Mutations
        class RemoveMember < OrganizationMutation
          requires :support

          argument :organization, ID
          argument :uuid, ID

          field :organization, Types::OrganizationType, null: false

          def resolve(organization:, uuid:)
            held = organization!(organization)
            actor = actor!(uuid)
            membership = member!(held, actor)

            refuse!(membership.errors.full_messages.join("; ")) unless membership.destroy

            Masks::Server::Token.live.where(organization: held, actor: actor).find_each(&:revoke!)

            audit!(Masks::Server::Event::MEMBERSHIP_REMOVED, actor: actor, organization: held.key, role: membership.role)

            { organization: held }
          end
        end
      end
    end
  end
end
