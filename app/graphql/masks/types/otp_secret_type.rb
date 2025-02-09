# frozen_string_literal: true

module Masks::Types
  class OtpSecretType < BaseObject
    field :id, ID
    field :name, String
    field :created_at, GraphQL::Types::ISO8601DateTime, null: true
    field :verified_at, GraphQL::Types::ISO8601DateTime, null: true

    def id
      object.public_id
    end
  end
end
