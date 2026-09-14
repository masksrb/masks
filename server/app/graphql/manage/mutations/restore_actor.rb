module Manage
  module Mutations
    class RestoreActor < BaseMutation
      argument :uuid, ID

      field :actor, Types::ActorType, null: false

      def resolve(uuid:)
        actor = actor!(uuid)

        refuse!("#{actor.identifier} is not suspended") unless actor.suspended?

        actor.restore!
        audit!(::Event::ACTOR_RESTORED, actor: actor)

        { actor: actor }
      end
    end
  end
end
