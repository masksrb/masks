module Manage
  module Mutations
    class SuspendActor < BaseMutation
      argument :uuid, ID

      field :actor, Types::ActorType, null: false

      def resolve(uuid:)
        actor = actor!(uuid)

        refuse!("that is you, and suspending yourself would lock you out") if actor.id == viewer.id
        refuse!("#{actor.identifier} is already suspended") if actor.suspended?

        actor.suspend!
        audit!(::Event::ACTOR_SUSPENDED, actor: actor)

        { actor: actor }
      end
    end
  end
end
