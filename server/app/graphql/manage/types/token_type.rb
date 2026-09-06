module Manage
  module Types
    class TokenType < BaseObject
      KINDS = {
        "AccessToken" => "access",
        "RefreshToken" => "refresh",
        "AuthorizationCode" => "code"
      }.freeze

      GRANTS = KINDS.keys.freeze

      field :id, ID, null: false
      field :kind, String, null: false
      field :actor, ActorType
      field :client, ClientType
      field :device, "Manage::Types::DeviceType"
      field :session, "Manage::Types::SessionType"
      field :scopes, [ String ], null: false
      field :audience, [ String ], null: false
      field :live, Boolean, null: false
      field :parent_id, ID
      field :authenticated_at, GraphQL::Types::ISO8601DateTime
      field :expires_at, GraphQL::Types::ISO8601DateTime, null: false
      field :consumed_at, GraphQL::Types::ISO8601DateTime
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false

      def kind
        KINDS.fetch(object.type, object.type.underscore)
      end

      def scopes
        object.scope_list
      end

      def audience
        Array(object.audience)
      end

      def live
        object.live?
      end
    end
  end
end
