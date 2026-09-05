module Manage
  module Mutations
    class UploadAvatar < BaseMutation
      argument :uuid, ID
      argument :photo, Types::UploadType

      field :actor, Types::ActorType, null: false

      def resolve(uuid:, photo:)
        actor = actor!(uuid)

        Avatar.store!(actor: actor, upload: photo)

        { actor: actor }
      rescue Avatar::Unreadable => e
        refuse!(e.message)
      end
    end
  end
end
