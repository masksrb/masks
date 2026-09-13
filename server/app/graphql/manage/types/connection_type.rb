module Manage
  module Types
    class ConnectionType < BaseObject
      field :id, ID, null: false
      field :provider, ProviderType, null: false
      field :actor, ActorType, null: false
      field :subject, String, null: false
      field :label, String
      field :email, String
      field :email_verified, Boolean, null: false
      field :connected_at, GraphQL::Types::ISO8601DateTime
      field :signed_in_at, GraphQL::Types::ISO8601DateTime
      field :revoked_at, GraphQL::Types::ISO8601DateTime
      field :revoked_reason, String
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false

      def id
        object.uuid
      end
    end
  end
end
