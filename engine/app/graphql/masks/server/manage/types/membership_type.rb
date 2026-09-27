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
          field :invited_as, String, description: "The address an invitation went to. Only that address can accept it."
          field :provisioned, Boolean, null: false, description: "True when a directory added this member through SCIM."
          field :invited_at, GraphQL::Types::ISO8601DateTime, description: "When the invitation was last sent."
          field :expires_at, GraphQL::Types::ISO8601DateTime,
                description: "When a pending invitation stops being accepted. Sending it again starts it over."
          field :expired, Boolean, null: false, method: :expired?,
                                   description: "True when the invitation can no longer be accepted."
          field :created_at, GraphQL::Types::ISO8601DateTime, null: false
        end
      end
    end
  end
end
