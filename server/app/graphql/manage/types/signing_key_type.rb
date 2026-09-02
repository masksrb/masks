module Manage
  module Types
    class SigningKeyType < BaseObject
      field :kid, ID, null: false
      field :algorithm, String, null: false
      field :activated_at, GraphQL::Types::ISO8601DateTime
      field :retired_at, GraphQL::Types::ISO8601DateTime
      field :retired, Boolean, null: false
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false

      def retired
        object.retired?
      end
    end
  end
end
