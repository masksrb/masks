module Masks
  module Server
    module Manage
      module Types
        class DelegationType < BaseObject
          field :id, ID, null: false
          field :client, ClientType, null: false
          field :actor, ActorType, null: false
          field :connection, ConnectionType, null: false
          field :provider, ProviderType, null: false
          field :scopes, [ String ], null: false
          field :consented_at, GraphQL::Types::ISO8601DateTime, null: false
          field :released_at, GraphQL::Types::ISO8601DateTime
          field :revoked_at, GraphQL::Types::ISO8601DateTime
          field :revoked_reason, String

          def id
            object.uuid
          end

          def provider
            object.connection.provider
          end

          def scopes
            Scopes.list(object.scopes)
          end
        end
      end
    end
  end
end
