module Masks
  module Server
    module Manage
      module Types
        class GroupMemberType < BaseObject
          description "A person's place in a group, and what put them there."

          field :group, GroupType, null: false
          field :actor, ActorType, null: false
          field :sourced_by, String, description: "rule, provider, or group when the group's source put them in. Null when a manager added them by hand."
          field :created_at, GraphQL::Types::ISO8601DateTime, null: false
        end
      end
    end
  end
end
