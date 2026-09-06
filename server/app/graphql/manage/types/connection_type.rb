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
      field :scopes, [ String ], null: false
      field :connected_at, GraphQL::Types::ISO8601DateTime
      field :signed_in_at, GraphQL::Types::ISO8601DateTime
      field :revoked_at, GraphQL::Types::ISO8601DateTime
      field :revoked_reason, String
      field :refreshable, Boolean, null: false
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false

      def id
        object.uuid
      end

      def scopes
        object.scope_list
      end

      def refreshable
        object.refresh_token.present?
      end
    end
  end
end
