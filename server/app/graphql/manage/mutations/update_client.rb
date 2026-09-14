module Manage
  module Mutations
    class UpdateClient < BaseMutation
      argument :client_id, ID
      argument :name, String, required: false
      argument :grant_types, [ String ], required: false
      argument :redirect_uris, [ String ], required: false
      argument :post_logout_redirect_uris, [ String ], required: false
      argument :resources, [ String ], required: false
      argument :required_scopes, [ String ], required: false
      argument :allowed_scopes, [ String ], required: false
      argument :subject_type, String, required: false
      argument :dpop_bound_access_tokens, Boolean, required: false
      argument :sector_identifier_uri, String, required: false
      argument :backchannel_logout_uri, String, required: false
      argument :backchannel_logout_session_required, Boolean, required: false
      argument :require_pushed_authorization_requests, Boolean, required: false
      argument :jwks, GraphQL::Types::JSON, required: false
      argument :jwks_uri, String, required: false
      argument :require_signed_request_object, Boolean, required: false
      argument :token_endpoint_auth_method, String, required: false
      argument :saml_entity_id, String, required: false
      argument :saml_certificate, String, required: false
      argument :saml_name_id_format, String, required: false
      argument :saml_requests_signed, Boolean, required: false
      argument :saml_idp_initiated, Boolean, required: false
      argument :saml_attributes, GraphQL::Types::JSON, required: false
      argument :consent_required, Boolean, required: false
      argument :sign_in_policy, ID, required: false

      field :client, Types::ClientType, null: false

      def resolve(client_id:, required_scopes: nil, allowed_scopes: nil, sign_in_policy: nil,
                  token_endpoint_auth_method: nil, **attributes)
        client = client!(client_id)

        authenticates!(client, token_endpoint_auth_method) if token_endpoint_auth_method

        unless sign_in_policy.nil?
          client.sign_in_policy = sign_in_policy.empty? ? nil : sign_in_policy!(sign_in_policy)

          refuse!("#{client.sign_in_policy.name} is archived") if client.sign_in_policy&.archived?
        end

        client.assign_attributes(attributes)
        client.response_types = client.default_response_types if attributes.key?(:grant_types)
        client.required_scopes = Scopes.join(required_scopes) unless required_scopes.nil?
        client.allowed_scopes = Scopes.join(allowed_scopes) unless allowed_scopes.nil?

        reserved = Scopes.reserved(client.scope_list)

        if reserved.any? && !client.approved?
          refuse!("#{Scopes.join(reserved)} may only be granted to an approved client")
        end

        save!(client)

        audit!(::Event::CLIENT_UPDATED, client: client, name: client.name)

        { client: client }
      end

      private

        def authenticates!(client, method)
          if client.public? || method == "none"
            refuse!("a public client stays public, and a confidential one stays confidential")
          end

          client.token_endpoint_auth_method = method
          client.secret_digest = nil unless client.secret?
        end
    end
  end
end
