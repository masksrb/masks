module Masks
  module Server
    module SamlIdentity
      class SignOff
        attr_reader :id, :client

        def initialize(issuer:, client:, name_id:, name_id_format:, session_index:)
          @issuer = issuer
          @client = client
          @name_id = name_id
          @name_id_format = name_id_format
          @session_index = session_index
          @id = SamlIdentity.identifier
        end

        def destination
          client.saml_slo_url
        end

        def encoded
          @encoded ||= Base64.strict_encode64(SamlIdentity.sign(issuer, to_xml))
        end

        private

          attr_reader :issuer, :name_id, :name_id_format, :session_index

          def to_xml
            now = Time.current

            Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
              xml["samlp"].LogoutRequest(
                "xmlns:samlp" => PROTOCOL_NS, "xmlns:saml" => ASSERTION_NS, "ID" => id, "Version" => "2.0",
                "IssueInstant" => SamlIdentity.instant(now), "NotOnOrAfter" => SamlIdentity.instant(now + LIFETIME),
                "Destination" => destination, "Reason" => "urn:oasis:names:tc:SAML:2.0:logout:user"
              ) do
                xml["saml"].Issuer(SamlIdentity.entity_id(issuer))
                xml["saml"].NameID(name_id, Format: name_id_format)
                xml["samlp"].SessionIndex(session_index)
              end
            end.doc.root.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)
          end
      end
    end
  end
end
