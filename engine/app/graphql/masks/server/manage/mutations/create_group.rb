module Masks
  module Server
    module Manage
      module Mutations
        class CreateGroup < BaseMutation
          requires :security

          argument :key, String, description: "Lowercase letters, digits, dots, dashes, and underscores. Apps see it in the groups claim."
          argument :name, String

          field :group, Types::GroupType, null: false

          def resolve(key:, name:)
            group = Masks::Server::Group.new(key: key, name: name)
            save!(group)

            audit!(Masks::Server::Event::GROUP_CREATED, group: group.key)

            { group: group }
          end
        end
      end
    end
  end
end
