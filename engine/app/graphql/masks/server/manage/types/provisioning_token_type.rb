module Masks
  module Server
    module Manage
      module Types
        class ProvisioningTokenType < BaseObject
          field :id, ID, null: false
          field :label, String, null: false
          field :issued_by, ActorType
          field :used_at, GraphQL::Types::ISO8601DateTime
          field :expires_at, GraphQL::Types::ISO8601DateTime, null: false
          field :created_at, GraphQL::Types::ISO8601DateTime, null: false
        end
      end
    end
  end
end
