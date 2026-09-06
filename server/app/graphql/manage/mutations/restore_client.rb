module Manage
  module Mutations
    class RestoreClient < BaseMutation
      argument :client_id, ID

      field :client, Types::ClientType, null: false

      def resolve(client_id:)
        client = client!(client_id)

        refuse!("#{client.name} is not archived") if client.archived_at.nil?

        taken = client.resources.filter_map { |resource| holder(resource, client) }.uniq

        if taken.any?
          refuse!(
            "#{taken.map(&:name).join(', ')} answers for #{client.resources.join(', ')} now; " \
            "archive it first"
          )
        end

        client.archived_at = nil
        save!(client)

        audit!(::Event::CLIENT_RESTORED, client: client, name: client.name)

        { client: client }
      end

      private

        def holder(resource, client)
          held = ::Client.approved_for(resource)

          held if held && held.id != client.id
        end
    end
  end
end
