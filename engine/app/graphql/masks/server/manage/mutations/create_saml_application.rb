module Masks
  module Server
    module Manage
      module Mutations
        class CreateSamlApplication < BaseMutation
          argument :name, String
          argument :entity_id, String
          argument :acs_urls, [ String ]
          argument :certificate, String, required: false
          argument :name_id_format, String, required: false
          argument :requests_signed, Boolean, required: false
          argument :idp_initiated, Boolean, required: false
          argument :attributes, GraphQL::Types::JSON, required: false

          field :client, Types::ClientType, null: false

          def resolve(name:, entity_id:, acs_urls:, certificate: nil, name_id_format: nil, requests_signed: false,
                      idp_initiated: false, attributes: nil)
            client = Masks::Server::Client.new(
              client_id: SecureRandom.uuid,
              name: name,
              protocol: SamlIdentity::PROTOCOL,
              saml_entity_id: entity_id,
              redirect_uris: acs_urls.map(&:strip).compact_blank,
              saml_certificate: certificate.presence,
              saml_name_id_format: name_id_format.presence,
              saml_requests_signed: requests_signed,
              saml_idp_initiated: idp_initiated,
              saml_attributes: attributes.presence || {},
              grant_types: [],
              response_types: [],
              token_endpoint_auth_method: "none",
              allowed_scopes: Scopes.join(SamlIdentity::SCOPES),
              dynamic: false,
              approved_at: Time.current,
              approved_by: viewer
            )

            save!(client)
            audit!(Masks::Server::Event::CLIENT_CREATED, client: client, name: client.name, protocol: client.protocol)

            { client: client }
          end
        end
      end
    end
  end
end
