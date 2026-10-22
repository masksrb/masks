module Masks
  module Server
    module Manage
      module Types
        class TenantType < BaseObject
          field :uuid, ID, null: false
          field :subdomain, String, null: false
          field :custom_host, String, description: "The host sign-in is also served from, within a proven domain."
          field :origins, [ String ], null: false, description: "Every origin this tenant answers on, each its own issuer."

          def origins
            [ object.templated_origin || object.held_origin, object.custom_origin ].compact
          end
          field :name, String, null: false
          field :named_by, String, null: false
          field :browsers_only, Boolean, null: false
          field :blocked_agents, String
          field :mails, Boolean, null: false
          field :accent_color, String
          field :key_rotation_days, Integer, description: "Days between scheduled signing key rotations, or null when a manager rotates by hand."
          field :logo_url, String, description: "The tenant's logo, 128 pixels square, or null for its initial."
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
          field :invitation_lifetime, Integer, null: false, description: "Seconds an invitation to an account stays valid."
          field :organization_invitation_lifetime, Integer, null: false,
                                                            description: "Seconds an invitation to an organization stays open after it was last sent."
          field :password_reset_lifetime, Integer, null: false, description: "Seconds a password reset link stays valid."
          field :email_verification_lifetime, Integer, null: false, description: "Seconds an email confirmation link stays valid."
          field :ldap_enabled, Boolean, null: false, description: "Whether the LDAP directory answers for this tenant.", method: :ldap?
          field :ldap_password_only, Boolean, null: false,
                                     description: "Whether a password alone binds to LDAP for an account that would otherwise need a second factor.",
                                     method: :ldap_password_only?
          field :created_at, GraphQL::Types::ISO8601DateTime, null: false
          field :signing_keys, [ SigningKeyType ], null: false

          def logo_url
            object.logo_url(size: 128)
          end

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
