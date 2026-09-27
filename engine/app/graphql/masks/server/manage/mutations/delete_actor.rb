module Masks
  module Server
    module Manage
      module Mutations
        class DeleteActor < BaseMutation
          argument :uuid, ID

          field :uuid, ID, null: false
          field :identifier, String, null: false

          def resolve(uuid:)
            actor = actor!(uuid)

            if actor.id == viewer.id
              refuse!("that is you, and deleting yourself would lock you out")
            end

            held = { uuid: actor.uuid, identifier: actor.identifier }

            actor.destroy!
            audit!(Masks::Server::Event::ACTOR_DELETED, **held)

            held
          end
        end
      end
    end
  end
end
