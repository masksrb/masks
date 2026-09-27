module Masks
  module Server
    module Manage
      module Types
        class TenantType < BaseObject
          field :uuid, ID, null: false
          field :subdomain, String, null: false
          field :name, String, null: false
          field :named_by, String, null: false
          field :browsers_only, Boolean, null: false
          field :blocked_agents, String
          field :mails, Boolean, null: false
          field :texts, Boolean, null: false
          field :sign_in_policy, SignInPolicyType
          field :dynamic_registration, String, null: false
          field :dynamic_client_scopes, [ String ]
          field :suspend_after, Integer
          field :delete_after, Integer
          field :risky_networks, String, description: "Address ranges that add to a sign-in's risk score, one per line."
          field :event_retention_days, Integer, null: false, description: "Days events are kept before they are deleted."

          def event_retention_days
            object.event_retention.in_days.round
          end
          field :created_at, GraphQL::Types::ISO8601DateTime, null: false
          field :signing_keys, [ SigningKeyType ], null: false

          def mails
            object.mails?
          end

          def texts
            object.texts?
          end

          def dynamic_client_scopes
            object.dynamic_client_scopes.presence && Scopes.list(object.dynamic_client_scopes)
          end

          def signing_keys
            object.signing_keys.published
          end
        end
      end
    end
  end
end
