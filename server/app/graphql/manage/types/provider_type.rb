module Manage
  module Types
    class ProviderType < BaseObject
      field :key, ID, null: false
      field :name, String, null: false
      field :authorization_url, String, null: false
      field :token_url, String, null: false
      field :revocation_url, String
      field :userinfo_url, String
      field :client_id, String, null: false
      field :scopes, [ String ], null: false
      field :authorize_params, GraphQL::Types::JSON, null: false
      field :subject_claim, String, null: false
      field :label_claim, String, null: false
      field :release_scope, String, null: false
      field :secret_held, Boolean, null: false
      field :connections, Integer, null: false
      field :signed_in, Integer, null: false
      field :archived_at, GraphQL::Types::ISO8601DateTime
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false

      field :issuer, String
      field :jwks_uri, String
      field :jwks_fetched_at, GraphQL::Types::ISO8601DateTime
      field :signs_in, Boolean, null: false
      field :provisions, Boolean, null: false
      field :email_domains, [ String ], null: false
      field :signup_scopes, [ String ], null: false

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

      def connections
        ::Connection.live.where(provider_id: object.id).count
      end

      def signed_in
        ::Connection.live.where(provider_id: object.id).where.not(signed_in_at: nil).count
      end
    end
  end
end
