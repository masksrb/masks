module Masks
  module Server
    module Manage
      module Mutations
        class DeleteGroup < BaseMutation
          requires :security

          argument :key, String

          field :key, String, null: false

          def resolve(key:)
            group = Masks::Server::Group.find_by(key: key) || refuse!("no group with that key")
            group.destroy!

            audit!(Masks::Server::Event::GROUP_DELETED, group: key)

            { key: key }
          end
        end
      end
    end
  end
end
