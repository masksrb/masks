module Manage
  module Mutations
    class RotateClientSecret < BaseMutation
      argument :client_id, ID
      argument :expires_in, Integer, required: false

      field :client, Types::ClientType, null: false
      field :secret, String, null: false

      def resolve(client_id:, expires_in: nil)
        client = client!(client_id)

        refuse!("a public client has no secret to rotate") if client.public?

        secret = client.issue_secret!
        client.secret_expires_at = expires_in && expires_in.seconds.from_now
        save!(client)

        audit!(::Event::CLIENT_SECRET_ROTATED, client: client, name: client.name)

        { client: client, secret: secret }
      end
    end
  end
end
