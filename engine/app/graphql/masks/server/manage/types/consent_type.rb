module Masks
  module Server
    module Manage
      module Types
        class ConsentType < BaseObject
          field :id, ID, null: false
          field :actor, ActorType, null: false
          field :client, ClientType, null: false
          field :scopes, [ String ], null: false
          field :audience, [ String ], null: false
          field :authorization_details, GraphQL::Types::JSON, null: false,
                description: "The authorization details the person allowed this client to ask for again without asking them, each with the time it expires."
          field :expires_at, GraphQL::Types::ISO8601DateTime,
                description: "When this consent ends and the person is asked again. Null lasts until revoked."
          field :revoked_at, GraphQL::Types::ISO8601DateTime
          field :created_at, GraphQL::Types::ISO8601DateTime, null: false
          field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

          def scopes
            Scopes.list(object.scopes)
          end

          def audience
            Array(object.audience)
          end
        end
      end
    end
  end
end
