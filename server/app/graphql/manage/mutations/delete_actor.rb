module Manage
  module Mutations
    class DeleteActor < BaseMutation
      argument :uuid, ID

      field :uuid, ID, null: false
      field :nickname, String, null: false

      def resolve(uuid:)
        actor = actor!(uuid)

        if actor.id == viewer.id
          refuse!("that is you, and deleting yourself would lock you out")
        end

        actor.destroy!

        { uuid: actor.uuid, nickname: actor.nickname }
      end
    end
  end
end
