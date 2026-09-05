module Manage
  module Mutations
    class BaseMutation < GraphQL::Schema::Mutation
      private

        def viewer
          context[:actor]
        end

        def refuse!(message)
          raise GraphQL::ExecutionError, message
        end

        def actor!(uuid)
          Actor.find_by(uuid: uuid) || refuse!("no actor with that uuid")
        end

        def client!(client_id)
          Client.find_by(client_id: client_id) || refuse!("no client with that client_id")
        end

        def device!(id)
          ::Device.find_by(id: id) || refuse!("no device with that id")
        end

        def save!(record)
          refuse!(record.errors.full_messages.join("; ")) unless record.save

          record
        end
    end
  end
end
