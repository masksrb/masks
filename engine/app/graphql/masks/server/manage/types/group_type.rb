module Masks
  module Server
    module Manage
      module Types
        class GroupType < BaseObject
          description "A named set of people in the tenant. The groups claim lists the key of each group a person is in."

          field :key, String, null: false
          field :name, String, null: false
          field :member_count, Integer, null: false
          field :members, [ ActorType ], null: false
          field :created_at, GraphQL::Types::ISO8601DateTime, null: false

          def member_count
            object.members.count
          end

          def members
            object.actors.order(:nickname)
          end
        end
      end
    end
  end
end
