module Manage
  module Types
    class ConsentType < BaseObject
      field :id, ID, null: false
      field :actor, ActorType, null: false
      field :client, ClientType, null: false
      field :scopes, [ String ], null: false
      field :audience, [ String ], null: false
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
