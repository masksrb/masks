module Manage
  module Mutations
    class GenerateBackupCodes < BaseMutation
      argument :uuid, ID

      field :actor, Types::ActorType, null: false
      field :codes, [ String ], null: false

      def resolve(uuid:)
        actor = actor!(uuid)

        unless actor.otp?
          refuse!("a backup code is a way past a second factor, and this actor has none")
        end

        { codes: actor.generate_backup_codes!, actor: actor }
      end
    end
  end
end
