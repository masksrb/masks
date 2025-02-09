# frozen_string_literal: true

module Masks::Types
  class LoginLinkType < BaseObject
    implements GraphQL::Types::Relay::Node

    field :email, String, null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: true
    field :expires_at, GraphQL::Types::ISO8601DateTime, null: false
    field :revoked_at, GraphQL::Types::ISO8601DateTime, null: true
    field :revoked, Boolean, null: false
    field :active, Boolean, null: false
    field :log_in, Boolean, null: true

    def email
      object.email&.address
    end

    def revoked
      object.revoked?
    end

    def active
      object.active?
    end
  end
end
