module Masks
  module Server
    module Manage
      module Types
        class OrganizationType < BaseObject
          field :uuid, ID, null: false
          field :key, ID, null: false
          field :name, String, null: false
          field :roles, [ String ], null: false, description: "Every role a member can hold here, owner and member included."
          field :members, [ "Masks::Server::Manage::Types::MembershipType" ], null: false
          field :member_count, Integer, null: false
          field :sign_in_policy, SignInPolicyType, description: "The policy for signing in as a member, ahead of the app's and the tenant's."
          field :providers, [ ProviderType ], null: false
          field :events, [ EventType ], null: false, description: "The organization's most recent events."
          field :archived_at, GraphQL::Types::ISO8601DateTime
          field :created_at, GraphQL::Types::ISO8601DateTime, null: false

          def roles
            object.role_list
          end

          def members
            object.memberships.includes(:actor).joins(:actor).order("actors.nickname", "actors.email")
          end

          def providers
            object.providers.active.order(:name)
          end

          def events
            Masks::Server::Event.where(organization: object).newest_first.includes(:actor, :by, :client, :device)
                                .limit(Masks::Server::Event::LIMIT)
          end

          def member_count
            object.memberships.accepted.count
          end
        end
      end
    end
  end
end
