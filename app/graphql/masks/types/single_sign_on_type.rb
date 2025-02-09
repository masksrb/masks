# frozen_string_literal: true

module Masks::Types
  class SingleSignOnType < BaseObject
    implements GraphQL::Types::Relay::Node

    field :id, ID, null: true
    field :identifier, String, null: true
    field :actor, ActorType, null: true
    field :provider, ProviderType, null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: true
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: true

    bool :deletable

    def id
      object.key
    end
  end
end
