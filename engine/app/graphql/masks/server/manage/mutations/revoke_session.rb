module Masks
  module Server
    module Manage
      module Mutations
        class RevokeSession < BaseMutation
          requires :support

          argument :id, ID

          field :session, Types::SessionType, null: false

          def resolve(id:)
            session = Session.find_by(id: id) || refuse!("no session with that id")
            managed!(session.actor)

            session.revoke!
            audit!(Masks::Server::Event::SESSION_REVOKED, actor: session.actor, device: session.device)

            { session: session }
          end
        end
      end
    end
  end
end
