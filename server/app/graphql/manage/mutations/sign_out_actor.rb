module Manage
  module Mutations
    class SignOutActor < BaseMutation
      argument :uuid, ID

      field :actor, Types::ActorType, null: false

      def resolve(uuid:)
        actor = actor!(uuid)

        actor.sign_out_everywhere!

        { actor: actor }
      end
    end
  end
end
