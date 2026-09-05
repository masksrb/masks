module Manage
  module Types
    class SigningKeyType < BaseObject
      field :kid, ID, null: false
      field :algorithm, String, null: false
      field :activated_at, GraphQL::Types::ISO8601DateTime
      field :retired_at, GraphQL::Types::ISO8601DateTime
      field :state, String, null: false
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false

      def state
        return "staged" if object.staged?
        return "active" if object.active?

        object.retired? ? "retired" : "retiring"
      end
    end
  end
end
