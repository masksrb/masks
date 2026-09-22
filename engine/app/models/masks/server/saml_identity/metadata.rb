module Masks
  module Server
    module SamlIdentity
      class Metadata
        def initialize(issuer)
          @issuer = issuer
        end

        def to_xml
          Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
            xml["md"].EntityDescriptor("xmlns:md" => METADATA_NS, "xmlns:ds" => DSIG_NS, "entityID" => SamlIdentity.entity_id(issuer)) do
              xml["md"].IDPSSODescriptor(WantAuthnRequestsSigned: "false", protocolSupportEnumeration: PROTOCOL_NS) do
                certificates.each do |certificate|
                  xml["md"].KeyDescriptor(use: "signing") do
                    xml["ds"].KeyInfo do
                      xml["ds"].X509Data { xml["ds"].X509Certificate(Base64.strict_encode64(certificate.to_der)) }
                    end
                  end
                end

                NAME_ID_FORMATS.each { |format| xml["md"].NameIDFormat(format) }

                xml["md"].SingleSignOnService(Binding: REDIRECT_BINDING, Location: SamlIdentity.sso_url(issuer))
                xml["md"].SingleSignOnService(Binding: POST_BINDING, Location: SamlIdentity.sso_url(issuer))
              end
            end
          end.to_xml
        end

        private

          attr_reader :issuer

          def certificates
            Tenant.switch(issuer.tenant) { SigningKey.published.map(&:certificate) }
          end
      end
    end
  end
end
