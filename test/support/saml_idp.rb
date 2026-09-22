module Masks
  module Server
    class SamlIdp
      PERSISTENT = "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent".freeze

      attr_reader :key, :certificate, :entity_id, :sso_url

      def initialize(entity_id: "https://idp.acme.test/saml", sso_url: "https://idp.acme.test/sso")
        @entity_id = entity_id
        @sso_url = sso_url
        @key = OpenSSL::PKey::RSA.generate(2048)
        @certificate = self.class.certificate_for(@key)
      end

      def self.certificate_for(key, name: "idp.acme.test")
        OpenSSL::X509::Certificate.new.tap do |certificate|
          certificate.version = 2
          certificate.serial = SecureRandom.random_number(2**64)
          certificate.subject = OpenSSL::X509::Name.parse("/CN=#{name}")
          certificate.issuer = certificate.subject
          certificate.public_key = key.public_key
          certificate.not_before = 1.day.ago
          certificate.not_after = 1.year.from_now
          certificate.sign(key, OpenSSL::Digest.new("SHA256"))
        end
      end

      def metadata
        <<~XML
          <?xml version="1.0"?>
          <md:EntityDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata" entityID="#{entity_id}">
            <md:IDPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
              <md:KeyDescriptor use="signing">
                <ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
                  <ds:X509Data><ds:X509Certificate>#{Base64.strict_encode64(certificate.to_der)}</ds:X509Certificate></ds:X509Data>
                </ds:KeyInfo>
              </md:KeyDescriptor>
              <md:SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" Location="#{sso_url}"/>
            </md:IDPSSODescriptor>
          </md:EntityDescriptor>
        XML
      end

      def response(in_response_to:, destination:, audience:, name_id:, attributes: {}, signer: key,
                   signed_certificate: certificate, sign: true, issuer: entity_id, lifetime: 5.minutes)
        now = Time.current.utc
        assertion = assertion_xml(
          in_response_to: in_response_to, destination: destination, audience: audience, name_id: name_id,
          attributes: attributes, issuer: issuer, now: now, lifetime: lifetime
        )

        if sign
          document = XMLSecurity::Document.new(assertion)
          document.sign_document(signer, signed_certificate, XMLSecurity::Document::RSA_SHA256, XMLSecurity::Document::SHA256)
          assertion = document.root.to_s
        end

        Base64.strict_encode64(<<~XML)
          <samlp:Response xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"
            ID="_#{SecureRandom.hex(16)}" Version="2.0" IssueInstant="#{now.iso8601}"
            Destination="#{destination}"#{%( InResponseTo="#{in_response_to}") if in_response_to}>
            <saml:Issuer>#{issuer}</saml:Issuer>
            <samlp:Status><samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Success"/></samlp:Status>
            #{assertion}
          </samlp:Response>
        XML
      end

      private

        def assertion_xml(in_response_to:, destination:, audience:, name_id:, attributes:, issuer:, now:, lifetime:)
          statements = attributes.map do |name, value|
            %(<saml:Attribute Name="#{name}"><saml:AttributeValue>#{CGI.escapeHTML(value.to_s)}</saml:AttributeValue></saml:Attribute>)
          end

          <<~XML
            <saml:Assertion xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" ID="_#{SecureRandom.hex(16)}" Version="2.0" IssueInstant="#{now.iso8601}">
              <saml:Issuer>#{issuer}</saml:Issuer>
              <saml:Subject>
                <saml:NameID Format="#{PERSISTENT}">#{name_id}</saml:NameID>
                <saml:SubjectConfirmation Method="urn:oasis:names:tc:SAML:2.0:cm:bearer">
                  <saml:SubjectConfirmationData#{%( InResponseTo="#{in_response_to}") if in_response_to} NotOnOrAfter="#{(now + lifetime).iso8601}" Recipient="#{destination}"/>
                </saml:SubjectConfirmation>
              </saml:Subject>
              <saml:Conditions NotBefore="#{(now - 1.minute).iso8601}" NotOnOrAfter="#{(now + lifetime).iso8601}">
                <saml:AudienceRestriction><saml:Audience>#{audience}</saml:Audience></saml:AudienceRestriction>
              </saml:Conditions>
              <saml:AuthnStatement AuthnInstant="#{now.iso8601}" SessionIndex="_#{SecureRandom.hex(8)}">
                <saml:AuthnContext><saml:AuthnContextClassRef>urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport</saml:AuthnContextClassRef></saml:AuthnContext>
              </saml:AuthnStatement>
              <saml:AttributeStatement>#{statements.join}</saml:AttributeStatement>
            </saml:Assertion>
          XML
        end
    end
  end
end
