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
      field :delegable, Boolean, null: false
      field :tokens_refreshed_at, GraphQL::Types::ISO8601DateTime
      field :delegations, [ "Manage::Types::DelegationType" ], null: false

      def id
        object.uuid
      end

      def delegable
        object.delegable?
      end

      def delegations
        object.delegations.live.includes(:client).order(created_at: :desc)
      end
    end
  end
end
