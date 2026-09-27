module Masks
  module Server
    module Manage
      module Mutations
        class UpdateEventStream < BaseMutation
          requires :security

          argument :key, ID
          argument :name, String, required: false
          argument :url, String, required: false
          argument :actions, [ String ], required: false
          argument :organization, ID, required: false, description: "An organization's key, to send only its events. An empty string sends every event."

          field :event_stream, Types::EventStreamType, null: false

          def resolve(key:, name: nil, url: nil, actions: nil, organization: nil)
            stream = event_stream!(key)

            refuse!("#{stream.name} is archived; restore it first") if stream.archived?

            stream.name = name unless name.nil?
            stream.url = url unless url.nil?
            stream.actions = actions unless actions.nil?
            stream.organization = organization_named(organization) unless organization.nil?

            save!(stream)

            audit!(Masks::Server::Event::STREAM_UPDATED, stream: stream.key,
                                                        changed: [ name && "name", url && "url", actions && "actions", organization && "organization" ].compact)

            { event_stream: stream }
          end
        end
      end
    end
  end
end
