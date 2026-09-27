module Masks
  module Server
    module Manage
      module Mutations
        class CreateEventStream < BaseMutation
          requires :security

          argument :key, ID
          argument :name, String
          argument :url, String
          argument :actions, [ String ], required: false

          field :event_stream, Types::EventStreamType, null: false
          field :secret, String, null: false

          def resolve(key:, name:, url:, actions: nil)
            refuse!("an event stream is already keyed #{key}") if Masks::Server::EventStream.exists?(key: key)

            stream = Masks::Server::EventStream.new(key: key, name: name, url: url, actions: actions || [])

            save!(stream)

            audit!(Masks::Server::Event::STREAM_CREATED, stream: stream.key)

            { event_stream: stream, secret: stream.secret }
          end
        end
      end
    end
  end
end
