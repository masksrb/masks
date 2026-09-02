module Manage
  module Mutations
    class SetActorScopes < BaseMutation
      argument :uuid, ID
      argument :scopes, [ String ]

      field :actor, Types::ActorType, null: false

      def resolve(uuid:, scopes:)
        actor = actor!(uuid)
        requested = Scopes.list(scopes)

        if actor.id == viewer.id && !requested.include?(Scopes::MANAGE)
          refuse!("you cannot take #{Scopes::MANAGE} away from yourself")
        end

        actor.scopes = Scopes.join(requested)

        { actor: save!(actor) }
      end
    end
  end
end
