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

        was = actor.scope_list
        actor.scopes = Scopes.join(requested)
        save!(actor)

        audit!(::Event::ACTOR_SCOPES_CHANGED, actor: actor, was: was, now: actor.scope_list)

        { actor: actor }
      end
    end
  end
end
