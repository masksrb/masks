module Masks
  module Server
    module Manage
      module Mutations
        class UpdateGroup < BaseMutation
          requires :security

          argument :key, String
          argument :name, String

          field :group, Types::GroupType, null: false

          def resolve(key:, name:)
            group = group!(key)
            group.name = name
            save!(group)

            { group: group }
          end
        end
      end
    end
  end
end
