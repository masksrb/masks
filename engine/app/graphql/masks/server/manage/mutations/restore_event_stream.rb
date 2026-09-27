module Masks
  module Server
    module Manage
      module Mutations
        class RestoreEventStream < BaseMutation
          argument :key, ID

          field :event_stream, Types::EventStreamType, null: false

          def resolve(key:)
            stream = event_stream!(key)

            refuse!("#{stream.name} is not archived") unless stream.archived?

            stream.archived_at = nil
            save!(stream)

            audit!(Masks::Server::Event::STREAM_UPDATED, stream: stream.key, changed: [ "restored" ])

            { event_stream: stream }
          end
        end
      end
    end
  end
end
