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
            group = group!(key)
            actor = actor!(uuid)

            group.remove!(actor, by: viewer)

            { group: group }
          rescue Masks::Server::Group::Sourced => e
            refuse!(e.message)
          end
        end
      end
    end
  end
end
