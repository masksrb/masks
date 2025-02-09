# frozen_string_literal: true

module Masks::Types
  class DeviceType < BaseObject
    implements GraphQL::Types::Relay::Node

    field :id, ID
    field :name, String
    field :type, String
    field :os, String
    field :ip, String
    field :user_agent, String
    field :version, String
    field :actors, [ActorType], null: false
    field :tokens, [TokenType], null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    field :blocked_at, GraphQL::Types::ISO8601DateTime, null: true

    def id
      object.public_id
    end

    def type
      object.device_type
    end

    def os
      object.os_name
    end

    def ip
      object.ip_address
    end
  end
end
