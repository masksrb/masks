module Masks
  module Server
    module Manage
      module Mutations
        class RefreshGroup < BaseMutation
          requires :security

          description "Fills a sourced group now instead of waiting for the hourly run."

          argument :key, String

          field :group, Types::GroupType, null: false

          def resolve(key:)
            { group: group!(key).refresh!(by: viewer) }
          end
        end
      end
    end
  end
end
