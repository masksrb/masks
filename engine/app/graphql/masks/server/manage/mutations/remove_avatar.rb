module Masks
  module Server
    module Manage
      module Mutations
        class RemoveAvatar < BaseMutation
          argument :uuid, ID

          field :actor, Types::ActorType, null: false

          def resolve(uuid:)
            actor = actor!(uuid)
            held = Masks::Server::Avatars.photo(actor)

            refuse!("that actor has no photo") if held.nil?

            held.destroy!
            audit!(Masks::Server::Event::AVATAR_REMOVED, actor: actor)

            { actor: actor.reload }
          end
        end
      end
    end
  end
end
