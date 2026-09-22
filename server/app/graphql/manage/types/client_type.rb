module Manage
  module Types
    class ClientType < BaseObject
      field :client_id, ID, null: false
      field :name, String, null: false
      field :redirect_uris, [ String ], null: false
      field :post_logout_redirect_uris, [ String ], null: false
      field :grant_types, [ String ], null: false
      field :response_types, [ String ], null: false
      field :resources, [ String ], null: false
      field :required_scopes, [ String ], null: false
      field :allowed_scopes, [ String ], null: false
      field :namespaces, [ "Manage::Types::NamespaceType" ], null: false
      field :token_endpoint_auth_method, String, null: false
      field :subject_type, String, null: false
      field :dpop_bound_access_tokens, Boolean, null: false
      field :sector_identifier_uri, String
      field :application_type, String, null: false
      field :client_uri, String
      field :logo_uri, String
      field :tos_uri, String
      field :policy_uri, String
      field :logo_url, String do
        argument :size, Integer, required: false
      end
      field :backchannel_logout_uri, String
      field :backchannel_logout_session_required, Boolean, null: false
      field :require_pushed_authorization_requests, Boolean, null: false
      field :jwks, GraphQL::Types::JSON
      field :jwks_uri, String
      field :protocol, String, null: false
      field :saml_entity_id, String
      field :saml_certificate, String
      field :saml_name_id_format, String
      field :saml_requests_signed, Boolean, null: false
      field :saml_idp_initiated, Boolean, null: false
      field :saml_attributes, GraphQL::Types::JSON, null: false
      field :require_signed_request_object, Boolean, null: false
      field :consent_required, Boolean, null: false
      field :sign_in_policy, SignInPolicyType
      field :dynamic, Boolean, null: false
      field :approved_at, GraphQL::Types::ISO8601DateTime
      field :approved_by, ActorType
      field :archived_at, GraphQL::Types::ISO8601DateTime
      field :secret_expires_at, GraphQL::Types::ISO8601DateTime
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false

      field :delegations, [ "Manage::Types::DelegationType" ], null: false

      field :consents, [ "Manage::Types::ConsentType" ], null: false do
        argument :limit, Integer, required: false
      end

      field :tokens, [ "Manage::Types::TokenType" ], null: false do
        argument :limit, Integer, required: false
      end

      field :events, [ "Manage::Types::EventType" ], null: false do
        argument :limit, Integer, required: false
      end

      def tokens(limit: nil)
        ::Token.where(kind: TokenType::GRANTS, client_id: object.id)
               .live
               .includes(:actor, :device)
               .order(created_at: :desc)
               .limit(limit || QueryType::LIMIT)
      end

      def delegations
        ::Delegation.live.where(client_id: object.id).includes(:actor, connection: :provider).order(created_at: :desc)
      end

      def consents(limit: nil)
        ::Consent.live
                 .where(client_id: object.id)
                 .includes(:actor)
                 .order(updated_at: :desc)
                 .limit(limit || QueryType::LIMIT)
      end

      def events(limit: nil)
        ::Event
          .where(client_id: object.id)
          .newest_first
          .includes(:actor, :by, :device)
          .limit(::Event.bounded(limit))
      end

      def logo_url(size: nil)
        object.logo_url(context[:actor], size: size)
      end

      def required_scopes
        Scopes.list(object.required_scopes)
      end

      def allowed_scopes
        Scopes.list(object.allowed_scopes)
      end
    end
  end
end
