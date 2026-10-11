module Masks
  module Server
    module Manage
      module Mutations
        class AddGroupMember < BaseMutation
          requires :security

          argument :key, String
          argument :uuid, ID

          field :group, Types::GroupType, null: false

          def resolve(key:, uuid:)
            group = group!(key)
            actor = actor!(uuid)

            group.add!(actor, by: viewer)

            { group: group }
          end
        end
      end
    end
  end
end
