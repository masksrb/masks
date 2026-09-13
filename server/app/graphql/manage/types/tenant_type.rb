module Manage
  module Types
    class TenantType < BaseObject
      field :uuid, ID, null: false
      field :subdomain, String, null: false
      field :name, String, null: false
      field :named_by, String, null: false
      field :browsers_only, Boolean, null: false
      field :blocked_agents, String
      field :mails, Boolean, null: false
      field :texts, Boolean, null: false
      field :dynamic_registration, String, null: false
      field :dynamic_client_scopes, [ String ]
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :signing_keys, [ SigningKeyType ], null: false

      def mails
        object.mails?
      end

      def texts
        object.texts?
      end

      def dynamic_client_scopes
        object.dynamic_client_scopes.presence && Scopes.list(object.dynamic_client_scopes)
      end

      def signing_keys
        object.signing_keys.published
      end
    end
  end
end
