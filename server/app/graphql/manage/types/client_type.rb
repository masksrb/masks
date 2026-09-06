module Manage
  module Types
    class ClientType < BaseObject
      field :client_id, ID, null: false
      field :name, String, null: false
      field :redirect_uris, [ String ], null: false
      field :post_logout_redirect_uris, [ String ], null: false
      field :grant_types, [ String ], null: false
      field :response_types, [ String ], null: false
      field :resources, [ String ], null: false
      field :required_scopes, [ String ], null: false
      field :allowed_scopes, [ String ], null: false
      field :namespaces, [ "Manage::Types::NamespaceType" ], null: false
      field :token_endpoint_auth_method, String, null: false
      field :application_type, String, null: false
      field :client_uri, String
      field :logo_uri, String
      field :tos_uri, String
      field :policy_uri, String
      field :dynamic, Boolean, null: false
      field :approved_at, GraphQL::Types::ISO8601DateTime
      field :approved_by, ActorType
      field :archived_at, GraphQL::Types::ISO8601DateTime
      field :secret_expires_at, GraphQL::Types::ISO8601DateTime
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false

      def required_scopes
        Scopes.list(object.required_scopes)
      end

      def allowed_scopes
        Scopes.list(object.allowed_scopes)
      end
    end
  end
end
