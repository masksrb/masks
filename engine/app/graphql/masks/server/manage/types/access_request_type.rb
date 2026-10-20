module Masks
  module Server
    module Manage
      module Types
        class AccessRequestType < BaseObject
          description "An actor turned away from a client who asked for access. Granting it puts them in one of the groups the client allows."

          field :id, ID, null: false
          field :actor, ActorType, null: false
          field :client, ClientType, null: false
          field :label, String, description: "The group key, or organization role as key:role, the actor was put in. Null until granted."
          field :decided_by, ActorType
          field :granted_at, GraphQL::Types::ISO8601DateTime
          field :declined_at, GraphQL::Types::ISO8601DateTime
          field :open, Boolean, null: false, method: :open?, description: "True while nobody has granted or declined it."
          field :created_at, GraphQL::Types::ISO8601DateTime, null: false
        end
      end
    end
  end
end
