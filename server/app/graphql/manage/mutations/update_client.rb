module Manage
  module Mutations
    class UpdateClient < BaseMutation
      argument :client_id, ID
      argument :name, String, required: false
      argument :redirect_uris, [ String ], required: false
      argument :post_logout_redirect_uris, [ String ], required: false
      argument :resources, [ String ], required: false
      argument :required_scopes, [ String ], required: false
      argument :allowed_scopes, [ String ], required: false
      argument :subject_type, String, required: false
      argument :sector_identifier_uri, String, required: false
      argument :backchannel_logout_uri, String, required: false
      argument :backchannel_logout_session_required, Boolean, required: false
      argument :require_pushed_authorization_requests, Boolean, required: false

      field :client, Types::ClientType, null: false

      def resolve(client_id:, required_scopes: nil, allowed_scopes: nil, **attributes)
        client = client!(client_id)

        client.assign_attributes(attributes)
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
    end
  end
end
