module Masks
  module Server
    module Manage
      module Mutations
        class UpdateGroup < BaseMutation
          include GroupSource

          requires :security

          argument :key, String
          argument :name, String, required: false

          field :group, Types::GroupType, null: false

          def resolve(key:, name: nil, **source)
            group = group!(key)
            group.name = name unless name.nil?
            fill_source(group, **source)
            save!(group)

            { group: group.reload }
          end
        end
      end
    end
  end
end
