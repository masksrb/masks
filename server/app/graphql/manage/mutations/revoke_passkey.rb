module Manage
  module Mutations
    class RevokePasskey < BaseMutation
      argument :uuid, ID
      argument :id, ID

      field :actor, Types::ActorType, null: false

      def resolve(uuid:, id:)
        actor = actor!(uuid)
        passkey = ::Passkey.find_by(id: id, actor_id: actor.id)

        refuse!("that actor has no such passkey") if passkey.nil?

        passkey.destroy!

        { actor: actor.reload }
      end
    end
  end
end
