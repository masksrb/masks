module Manage
  module Mutations
    class ArchiveClient < BaseMutation
      argument :client_id, ID

      field :client, Types::ClientType, null: false

      def resolve(client_id:)
        client = client!(client_id)

        if client.id == context[:client]&.id
          refuse!("that is the client you are signed in with, and archiving it would lock you out")
        end

        client.archived_at = Time.current
        save!(client)

        audit!(::Event::CLIENT_ARCHIVED, client: client, name: client.name)

        { client: client }
      end
    end
  end
end
