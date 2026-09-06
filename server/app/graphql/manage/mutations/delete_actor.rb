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

        held = { uuid: actor.uuid, nickname: actor.nickname }

        actor.destroy!
        audit!(::Event::ACTOR_DELETED, **held)

        held
      end
    end
  end
end
