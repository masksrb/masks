module Masks
  module Server
    module Manage
      module Mutations
        class CreateActor < BaseMutation
          requires :support

          argument :nickname, String, required: false
          argument :email, String, required: false
          argument :password, String, required: false
          argument :scopes, [ String ], required: false

          field :actor, Types::ActorType, null: false
          field :delivered, Boolean, null: false
          field :url, String

          def resolve(nickname: nil, email: nil, password: nil, scopes: nil)
            granting!(scopes)

            actor = Actor.new(
              trusted_rename: true,
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
            actor_created!(actor, invited: false)

            Verifications.open(actor: actor, journey: Masks::Server::Journey.manage(viewer)).merge(actor: actor)
          end

          private

            def invite(actor)
              save!(actor)

              invited!(actor).merge(actor: actor)
            end
        end
      end
    end
  end
end
