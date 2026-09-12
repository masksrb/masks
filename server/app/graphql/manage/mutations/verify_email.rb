module Manage
  module Mutations
    class VerifyEmail < BaseMutation
      argument :uuid, ID

      field :actor, Types::ActorType, null: false
      field :delivered, Boolean, null: false
      field :url, String

      def resolve(uuid:)
        actor = actor!(uuid)

        refuse!("#{actor.identifier} has no email address") if actor.email.blank?
        refuse!("#{actor.email} is already confirmed") if actor.email_verified_at.present?

        Verifications.open(actor: actor, by: viewer).merge(actor: actor)
      end
    end
  end
end
