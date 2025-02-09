# frozen_string_literal: true

module Masks::Types
  class PhoneType < BaseObject
    field :number, String
    field :actor, ActorType, null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: true
    field :verified_at, GraphQL::Types::ISO8601DateTime, null: true
  end
end
