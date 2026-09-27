module Masks
  module Server
    module Manage
      module Types
        class MembershipType < BaseObject
          field :actor, ActorType, null: false
          field :organization, OrganizationType, null: false
          field :role, String, null: false
          field :pending, Boolean, null: false, description: "True until the person accepts. A pending membership grants nothing."
          field :invited_by, ActorType
          field :created_at, GraphQL::Types::ISO8601DateTime, null: false
        end
      end
    end
  end
end
