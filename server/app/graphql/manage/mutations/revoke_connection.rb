module Manage
  module Mutations
    class RevokeConnection < BaseMutation
      argument :id, ID

      field :connection, Types::ConnectionType, null: false

      def resolve(id:)
        connection = ::Connection.find_by(uuid: id) || refuse!("no connection with that id")

        connection.revoke!(reason: "revoked by #{viewer.identifier}")

        audit!(
          ::Event::CONNECTION_UNLINKED,
          actor: connection.actor, provider: connection.provider.key
        )

        { connection: connection }
      end
    end
  end
end
