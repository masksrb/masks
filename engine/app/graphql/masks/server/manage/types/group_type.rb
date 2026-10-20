module Masks
  module Server
    module Manage
      module Types
        class GroupType < BaseObject
          description "A named set of people in the tenant. The groups claim lists the key of each group a person is in. " \
                      "A group fills by hand, from a rule, from a provider, or from other groups."

          field :key, String, null: false
          field :name, String, null: false
          field :source, String, null: false, description: "manual, rule, provider, or group."
          field :rule, [ GroupConditionType ], null: false, description: "The conditions a rule group checks. Empty unless the source is rule."
          field :provider_key, String, description: "The provider a provider group reads at sign-in."
          field :upstream_group, String, description: "The group name the provider lists for people who belong."
          field :parent_labels, [ String ], null: false, description: "The group keys and organization roles, as key:role, a nested group holds everyone from."
          field :refreshed_at, GraphQL::Types::ISO8601DateTime, description: "When the source last filled the group."
          field :member_count, Integer, null: false
          field :members, [ ActorType ], null: false
          field :memberships, [ GroupMemberType ], null: false, description: "Each member with what put them in the group."
          field :created_at, GraphQL::Types::ISO8601DateTime, null: false

          def provider_key
            object.provider&.key
          end

          def member_count
            object.members.count
          end

          def members
            object.actors.order(:nickname)
          end

          def memberships
            object.members.includes(:actor).sort_by { |member| member.actor.nickname.to_s }
          end
        end
      end
    end
  end
end
