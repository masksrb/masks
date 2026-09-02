module Manage
  module Mutations
    class InviteActor < BaseMutation
      argument :nickname, String
      argument :email, String
      argument :scopes, [ String ], required: false

      field :actor, Types::ActorType, null: false
      field :delivered, Boolean, null: false
      field :url, String

      def resolve(nickname:, email:, scopes: nil)
        refuse!("an invitation needs an email address to send to") if email.blank?

        actor = Actor.new(
          nickname: nickname,
          email: email,
          scopes: Scopes.join(Scopes.list(scopes).presence || Scopes::STANDARD)
        )

        save!(actor)

        Invitations.open(actor: actor, by: viewer).merge(actor: actor)
      end
    end
  end
end
