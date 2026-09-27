module Masks
  module Server
    module Manage
      module Mutations
        class ArchiveEventStream < BaseMutation
          requires :security

          argument :key, ID

          field :event_stream, Types::EventStreamType, null: false

          def resolve(key:)
            stream = event_stream!(key)

            refuse!("#{stream.name} is already archived") if stream.archived?

            stream.archived_at = Time.current
            save!(stream)

            audit!(Masks::Server::Event::STREAM_ARCHIVED, stream: stream.key)

            { event_stream: stream }
          end
        end
      end
    end
  end
end
