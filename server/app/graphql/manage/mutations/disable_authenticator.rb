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

        save!(actor)
        DeviceFactor.forget!(actor: actor)
        audit!(::Event::AUTHENTICATOR_DISABLED, actor: actor)

        { actor: actor }
      end
    end
  end
end
