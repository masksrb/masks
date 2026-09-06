module Manage
  module Mutations
    class RevokeSession < BaseMutation
      argument :id, ID

      field :session, Types::SessionType, null: false

      def resolve(id:)
        session = Session.find_by(id: id) || refuse!("no session with that id")

        session.revoke!
        audit!(::Event::SESSION_REVOKED, actor: session.actor, device: session.device)

        { session: session }
      end
    end
  end
end
