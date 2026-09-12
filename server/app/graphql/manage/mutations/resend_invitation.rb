module Manage
  module Mutations
    class ResendInvitation < BaseMutation
      argument :uuid, ID

      field :actor, Types::ActorType, null: false
      field :delivered, Boolean, null: false
      field :url, String

      def resolve(uuid:)
        actor = actor!(uuid)

        refuse!("#{actor.identifier} has already accepted an invitation") if actor.activated?

        Invitations.open(actor: actor, by: viewer).merge(actor: actor)
      end
    end
  end
end
