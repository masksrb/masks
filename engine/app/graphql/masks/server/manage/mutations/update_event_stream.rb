module Masks
  module Server
    module Manage
      module Mutations
        class UpdateEventStream < BaseMutation
          argument :key, ID
          argument :name, String, required: false
          argument :url, String, required: false
          argument :actions, [ String ], required: false

          field :event_stream, Types::EventStreamType, null: false

          def resolve(key:, name: nil, url: nil, actions: nil)
            stream = event_stream!(key)

            refuse!("#{stream.name} is archived; restore it first") if stream.archived?

            stream.name = name unless name.nil?
            stream.url = url unless url.nil?
            stream.actions = actions unless actions.nil?

            save!(stream)

            audit!(Masks::Server::Event::STREAM_UPDATED, stream: stream.key,
                                                        changed: [ name && "name", url && "url", actions && "actions" ].compact)

            { event_stream: stream }
          end
        end
      end
    end
  end
end
