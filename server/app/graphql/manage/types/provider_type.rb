module Manage
  module Types
    class ProviderType < BaseObject
      field :key, ID, null: false
      field :name, String, null: false
      field :protocol, String, null: false
      field :preset, String
      field :authorization_url, String
      field :token_url, String
      field :userinfo_url, String
      field :client_id, String
      field :emails_url, String
      field :claims, GraphQL::Types::JSON, null: false
      field :token_auth_method, String, null: false
      field :response_mode, String
      field :team_id, String
      field :key_id, String
      field :private_key_held, Boolean, null: false
      field :callback_url, String, null: false
      field :idp_entity_id, String
      field :idp_sso_url, String
      field :idp_certificates, String
      field :metadata_url, String
      field :metadata_fetched_at, GraphQL::Types::ISO8601DateTime
      field :name_id_format, String
      field :sp_entity_id, String
      field :scopes, [ String ], null: false
      field :authorize_params, GraphQL::Types::JSON, null: false
      field :subject_claim, String, null: false
      field :secret_held, Boolean, null: false
      field :connections, Integer, null: false
      field :signed_in, Integer, null: false
      field :archived_at, GraphQL::Types::ISO8601DateTime
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false

      field :issuer, String
      field :jwks_uri, String
      field :jwks_fetched_at, GraphQL::Types::ISO8601DateTime
      field :role, String, null: false
      field :trusts_email, Boolean, null: false
      field :email_domains, [ String ], null: false
      field :signup_scopes, [ String ], null: false
      field :delegates, Boolean, null: false
      field :delegated_scopes, [ String ], null: false
      field :delegation_params, GraphQL::Types::JSON, null: false
      field :delegation_scope, String, null: false
      field :resource_url, String
      field :registration_url, String
      field :registered_at, GraphQL::Types::ISO8601DateTime
      field :delegations, Integer, null: false

      def scopes
        object.scope_list
      end

      def email_domains
        object.email_domain_list
      end

      def signup_scopes
        Scopes.list(object.signup_scopes)
      end

      def secret_held
        object.client_secret.present?
      end

      def sp_entity_id
        object.saml? ? object.federation.entity_id : nil
      end

      def private_key_held
        object.private_key.present?
      end

      def callback_url
        "#{Current.origin}/login/provider/#{object.key}/callback"
      end

      def connections
        ::Connection.live.where(provider_id: object.id).count
      end

      def delegated_scopes
        object.delegated_scope_list
      end

      def delegations
        ::Delegation.live.joins(:connection).where(connections: { provider_id: object.id }).count
      end

      def signed_in
        ::Connection.live.where(provider_id: object.id).where.not(signed_in_at: nil).count
      end
    end
  end
end
