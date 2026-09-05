module Manage
  module Types
    class SessionType < BaseObject
      field :id, ID, null: false
      field :actor, ActorType, null: false
      field :device, "Manage::Types::DeviceType"
      field :user_agent, String
      field :ip_address, String
      field :authenticated_at, GraphQL::Types::ISO8601DateTime
      field :expires_at, GraphQL::Types::ISO8601DateTime, null: false
      field :revoked_at, GraphQL::Types::ISO8601DateTime
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
