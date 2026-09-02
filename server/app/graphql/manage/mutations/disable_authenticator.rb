module Manage
  module Mutations
    class DisableAuthenticator < BaseMutation
      argument :uuid, ID

      field :actor, Types::ActorType, null: false

      def resolve(uuid:)
        actor = actor!(uuid)

        actor.assign_attributes(
          otp_secret: nil,
          otp_enabled_at: nil,
          backup_code_digests: [],
          backup_codes_generated_at: nil
        )

        { actor: save!(actor) }
      end
    end
  end
end
