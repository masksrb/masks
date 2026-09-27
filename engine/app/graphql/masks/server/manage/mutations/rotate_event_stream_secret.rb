module Masks
  module Server
    module Manage
      module Mutations
        class RotateEventStreamSecret < BaseMutation
          argument :key, ID

          field :event_stream, Types::EventStreamType, null: false
          field :secret, String, null: false

          def resolve(key:)
            stream = event_stream!(key)

            refuse!("#{stream.name} is archived; restore it first") if stream.archived?

            stream.rotate_secret!

            audit!(Masks::Server::Event::STREAM_SECRET_ROTATED, stream: stream.key)

            { event_stream: stream, secret: stream.secret }
          end
        end
      end
    end
  end
end
