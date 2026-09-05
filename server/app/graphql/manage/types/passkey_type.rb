module Manage
  module Types
    class PasskeyType < BaseObject
      field :id, ID, null: false
      field :label, String, null: false
      field :aaguid, String
      field :certification, String
      field :compromise, String
      field :user_verified, Boolean, null: false
      field :last_used_at, GraphQL::Types::ISO8601DateTime
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false

      def certification
        object.authenticator&.certification
      end
    end
  end
end
