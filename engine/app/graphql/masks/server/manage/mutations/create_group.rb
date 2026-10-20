module Masks
  module Server
    module Manage
      module Mutations
        class CreateGroup < BaseMutation
          include GroupSource

          requires :security

          argument :key, String, description: "Lowercase letters, digits, dots, dashes, and underscores. Apps see it in the groups claim."
          argument :name, String

          field :group, Types::GroupType, null: false

          def resolve(key:, name:, **source)
            group = fill_source(Masks::Server::Group.new(key: key, name: name), **source)
            save!(group)

            audit!(Masks::Server::Event::GROUP_CREATED, group: group.key, source: group.source)

            { group: group.reload }
          end
        end
      end
    end
  end
end
