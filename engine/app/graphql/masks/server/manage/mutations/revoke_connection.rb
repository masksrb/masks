module Masks
  module Server
    module Manage
      module Mutations
        class RevokeConnection < BaseMutation
          requires :support

          argument :id, ID

          field :connection, Types::ConnectionType, null: false

          def resolve(id:)
            connection = Masks::Server::Connection.find_by(uuid: id) || refuse!("no connection with that id")
            managed!(connection.actor)

            connection.revoke!(reason: "revoked by #{viewer.identifier}")

            audit!(
              Masks::Server::Event::CONNECTION_UNLINKED,
              actor: connection.actor, provider: connection.provider.key
            )

            { connection: connection }
          end
        end
      end
    end
  end
end
