module Masks
  module Server
    module Manage
      module Mutations
        class RestoreActor < BaseMutation
          argument :uuid, ID

          field :actor, Types::ActorType, null: false

          def resolve(uuid:)
            actor = actor!(uuid)

            refuse!("#{actor.identifier} is not suspended") unless actor.suspended?

            actor.restore!
            audit!(Masks::Server::Event::ACTOR_RESTORED, actor: actor)

            { actor: actor }
          end
        end
      end
    end
  end
end
