module Manage
  module Mutations
    class ApproveActor < BaseMutation
      argument :uuid, ID

      field :actor, Types::ActorType, null: false

      def resolve(uuid:)
        actor = actor!(uuid)

        refuse!("#{actor.identifier} is not waiting for approval") if actor.pending_approval_at.nil?

        ::Confirmations.approve!(actor, by: viewer)

        { actor: actor }
      end
    end
  end
end
