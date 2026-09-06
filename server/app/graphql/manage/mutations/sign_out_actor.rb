module Manage
  module Mutations
    class SignOutActor < BaseMutation
      argument :uuid, ID

      field :actor, Types::ActorType, null: false

      def resolve(uuid:)
        actor = actor!(uuid)

        actor.sign_out_everywhere!
        audit!(::Event::ACTOR_SIGNED_OUT, actor: actor)

        { actor: actor }
      end
    end
  end
end
