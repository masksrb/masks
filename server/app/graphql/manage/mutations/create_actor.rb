module Manage
  module Mutations
    class CreateActor < BaseMutation
      argument :nickname, String
      argument :email, String, required: false
      argument :password, String, required: false
      argument :scopes, [ String ], required: false

      field :actor, Types::ActorType, null: false
      field :delivered, Boolean, null: false
      field :url, String

      def resolve(nickname:, email: nil, password: nil, scopes: nil)
        actor = Actor.new(
          nickname: nickname,
          email: email,
          scopes: Scopes.join(Scopes.list(scopes).presence || Scopes::STANDARD)
        )

        return invite(actor) if password.blank?

        if password.length < Actor::MINIMUM_PASSWORD
          refuse!("a password needs at least #{Actor::MINIMUM_PASSWORD} characters")
        end

        actor.password = password
        save!(actor)
        created!(actor, invited: false)

        Verifications.open(actor: actor, by: viewer).merge(actor: actor)
      end

      private

        def invite(actor)
          save!(actor)
          created!(actor, invited: true)

          Invitations.open(actor: actor, by: viewer).merge(actor: actor)
        end

        def created!(actor, invited:)
          audit!(
            ::Event::ACTOR_CREATED,
            actor: actor, nickname: actor.nickname,
            scopes: actor.scope_list, invited: invited
          )
        end
    end
  end
end
