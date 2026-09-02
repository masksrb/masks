module Manage
  module Mutations
    class ResetPassword < BaseMutation
      argument :uuid, ID

      field :actor, Types::ActorType, null: false
      field :delivered, Boolean, null: false
      field :url, String

      def resolve(uuid:)
        actor = actor!(uuid)

        refuse!("#{actor.nickname} has not accepted an invitation yet") unless actor.activated?

        Recoveries.open(actor: actor, by: viewer).merge(actor: actor)
      end
    end
  end
end
