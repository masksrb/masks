module Masks
  module Server
    module Manage
      module Mutations
        class ReadSamlMetadata < BaseMutation
          argument :metadata_url, String, required: false
          argument :metadata_xml, String, required: false

          field :idp_entity_id, String, null: false
          field :idp_sso_url, String, null: false
          field :idp_certificates, String, null: false

          def resolve(metadata_url: nil, metadata_xml: nil)
            refuse!("pass a metadata URL or the metadata itself") if metadata_url.blank? && metadata_xml.blank?

            xml = metadata_xml.presence || fetch(metadata_url)
            parsed = Masks::Server::Federation::Saml.parse_metadata(xml)

            refuse!("that metadata names no single sign-on URL for the redirect binding") if parsed[:idp_sso_url].blank?
            refuse!("that metadata holds no signing certificate") if parsed[:idp_certificates].blank?

            parsed
          rescue Masks::Server::Provider::Untrusted, Masks::Server::Provider::Refused, Masks::Server::Provider::Unreachable => e
            refuse!(e.message)
          end

          private

            def fetch(url)
              probe = Masks::Server::Provider.new(name: "metadata", metadata_url: url, protocol: Masks::Server::Provider::SAML)
              probe.validate

              refuse!("metadata URL #{probe.errors[:metadata_url].first}") if probe.errors[:metadata_url].any?

              probe.fetch_text(url, Masks::Server::Federation::Saml::METADATA_LIMIT)
            end
        end
      end
    end
  end
end
