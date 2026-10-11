module Masks
  module Server
    module Manage
      module Mutations
        class DeleteGroup < BaseMutation
          requires :security

          argument :key, String

          field :key, String, null: false

          def resolve(key:)
            group = group!(key)
            group.destroy!

            audit!(Masks::Server::Event::GROUP_DELETED, group: key)

            { key: key }
          end
        end
      end
    end
  end
end
