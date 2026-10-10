module Masks
  module Server
    module Manage
      module Mutations
        class RemoveGroupMember < BaseMutation
          requires :security

          argument :key, String
          argument :uuid, ID

          field :group, Types::GroupType, null: false

          def resolve(key:, uuid:)
            group = Masks::Server::Group.find_by(key: key) || refuse!("no group with that key")
            actor = actor!(uuid)

            audit!(Masks::Server::Event::GROUP_LEFT, actor: actor, group: group.key) if group.remove!(actor)

            { group: group }
          end
        end
      end
    end
  end
end
