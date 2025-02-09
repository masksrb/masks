# frozen_string_literal: true

module Masks::Types
  class TokenType < BaseObject
    field :id, String, null: false
    field :name, String, null: true
    field :type, String, null: false
    field :secret, String, null: false
    field :nonce, String, null: true
    field :redirect_uri, String, null: true
    field :scopes, [String], null: true
    field :usable, Boolean, null: false
    field :expired, Boolean, null: false
    field :device, DeviceType, null: true
    field :actor, ActorType, null: true
    field :client, ClientType, null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: true
    field :expires_at, GraphQL::Types::ISO8601DateTime, null: true
    field :refreshed_at, GraphQL::Types::ISO8601DateTime, null: true
    field :revoked_at, GraphQL::Types::ISO8601DateTime, null: true

    def usable
      object.usable?
    end

    def expired
      object.expired?
    end

    def id
      object.public_id
    end

    def secret
      object.obfuscated_secret
    end

    def type
      object.public_type
    end

    def scopes
      object.scopes_a
    end
  end
end
