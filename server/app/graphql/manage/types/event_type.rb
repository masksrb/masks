module Manage
  module Types
    class EventType < BaseObject
      field :id, ID, null: false
      field :action, String, null: false
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :ip_address, String
      field :user_agent, String
      field :details, GraphQL::Types::JSON, null: false

      field :actor, ActorType
      field :by, ActorType
      field :client, ClientType
      field :device, DeviceType
    end
  end
end
