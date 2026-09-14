module Manage
  module Mutations
    class CreateClient < BaseMutation
      argument :name, String
      argument :grant_types, [ String ], required: false
      argument :redirect_uris, [ String ], required: false
      argument :post_logout_redirect_uris, [ String ], required: false
      argument :resources, [ String ], required: false
      argument :required_scopes, [ String ], required: false
      argument :allowed_scopes, [ String ], required: false
      argument :token_endpoint_auth_method, String, required: false
      argument :dpop_bound_access_tokens, Boolean, required: false
      argument :jwks, GraphQL::Types::JSON, required: false
      argument :jwks_uri, String, required: false
      argument :require_signed_request_object, Boolean, required: false

      field :client, Types::ClientType, null: false
      field :secret, String

      def resolve(name:, grant_types: [ ::Client::CLIENT_CREDENTIALS ], required_scopes: [], allowed_scopes: [],
                  token_endpoint_auth_method: ::Client::DEFAULT_AUTH_METHOD, **attributes)
        client = ::Client.new(
          client_id: SecureRandom.uuid,
          name: name,
          grant_types: grant_types,
          response_types: ::Client.response_types_for(grant_types),
          required_scopes: Scopes.join(required_scopes),
          allowed_scopes: Scopes.join(allowed_scopes),
          token_endpoint_auth_method: token_endpoint_auth_method,
          dynamic: false,
          approved_at: Time.current,
          approved_by: viewer,
          **attributes.compact
        )

        client.issue_secret! if client.secret?
        save!(client)

        audit!(::Event::CLIENT_CREATED, client: client, name: client.name, grant_types: client.grant_types)

        { client: client, secret: client.secret }
      end
    end
  end
end
