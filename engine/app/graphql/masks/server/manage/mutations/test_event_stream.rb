module Masks
  module Server
    module Manage
      module Mutations
        class TestEventStream < BaseMutation
          requires :security

          argument :key, ID

          field :delivered, Boolean, null: false
          field :failure, String

          def resolve(key:)
            stream = event_stream!(key)

            stream.ping!
            stream.delivered!

            audit!(Masks::Server::Event::STREAM_TESTED, stream: stream.key, delivered: true)

            { delivered: true, failure: nil }
          rescue Masks::Server::EventStream::Refused => failure
            stream.failed!(failure.message)

            audit!(Masks::Server::Event::STREAM_TESTED, stream: stream.key, delivered: false)

            { delivered: false, failure: failure.message }
          end
        end
      end
    end
  end
end
