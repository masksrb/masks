module SamlIdentity
  class Response
    attr_reader :issuer, :client, :destination, :in_response_to

    def initialize(issuer:, client:, destination:, in_response_to: nil)
      @issuer = issuer
      @client = client
      @destination = destination
      @in_response_to = in_response_to
      @now = Time.current.utc
    end

    def success(actor:, session:, name_id_format:, scopes:, authenticated_at:, amr:)
      assertion = sign(assertion_xml(actor, session, name_id_format, scopes, authenticated_at, amr))

      encode(sign(response_xml(SUCCESS) { |xml| xml << assertion }))
    end

    def failure(status, second = nil, message = nil)
      encode(sign(response_xml(status, second, message)))
    end

    private

      attr_reader :now

      def key
        @key ||= issuer.key
      end

      def entity
        SamlIdentity.entity_id(issuer)
      end

      def response_xml(status, second = nil, message = nil)
        Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
          xml["samlp"].Response(
            { "xmlns:samlp" => PROTOCOL_NS, "xmlns:saml" => ASSERTION_NS, "ID" => identifier, "Version" => "2.0",
              "IssueInstant" => instant(now), "Destination" => destination, "InResponseTo" => in_response_to }.compact
          ) do
            xml["saml"].Issuer(entity)
            xml["samlp"].Status do
              xml["samlp"].StatusCode(Value: status) do
                xml["samlp"].StatusCode(Value: second) if second
              end
              xml["samlp"].StatusMessage(message) if message
            end
            yield xml if block_given?
          end
        end.doc.root.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)
      end

      def assertion_xml(actor, session, name_id_format, scopes, authenticated_at, amr)
        claims = actor.claims(scopes, origin: issuer.url, subject: issuer.subject_for(actor, client))
        expires = now + LIFETIME

        Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
          xml["saml"].Assertion("xmlns:saml" => ASSERTION_NS, "ID" => identifier, "Version" => "2.0",
                                "IssueInstant" => instant(now)) do
            xml["saml"].Issuer(entity)
            xml["saml"].Subject do
              xml["saml"].NameID(name_id(actor, name_id_format), Format: name_id_format)
              xml["saml"].SubjectConfirmation(Method: "urn:oasis:names:tc:SAML:2.0:cm:bearer") do
                xml["saml"].SubjectConfirmationData(
                  { "NotOnOrAfter" => instant(expires), "Recipient" => destination, "InResponseTo" => in_response_to }.compact
                )
              end
            end
            xml["saml"].Conditions(NotBefore: instant(now - 1.minute), NotOnOrAfter: instant(expires)) do
              xml["saml"].AudienceRestriction { xml["saml"].Audience(client.saml_entity_id) }
            end
            xml["saml"].AuthnStatement({ "AuthnInstant" => instant(authenticated_at || now),
                                         "SessionIndex" => session&.uuid && "_#{session.uuid}" }.compact) do
              xml["saml"].AuthnContext do
                xml["saml"].AuthnContextClassRef(Array(amr).include?(Issuer::MULTI_FACTOR) ? MFA_CONTEXT : PASSWORD_CONTEXT)
              end
            end

            released = attributes(claims)

            if released.any?
              xml["saml"].AttributeStatement do
                released.each do |name, value|
                  xml["saml"].Attribute(Name: name, NameFormat: "urn:oasis:names:tc:SAML:2.0:attrname-format:basic") do
                    Array(value).each { |one| xml["saml"].AttributeValue(one.to_s) }
                  end
                end
              end
            end
          end
        end.doc.root.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)
      end

      def name_id(actor, format)
        case format
        when EMAIL
          raise Refused, "#{actor.identifier} has no confirmed email to be named by" unless actor.email.present? && actor.email_verified_at

          actor.email
        else
          issuer.subject_for(actor, client)
        end
      end

      def attributes(claims)
        mapping = client.saml_attributes.presence || DEFAULT_ATTRIBUTES

        confirmed = claims.except(*("email" unless claims["email_verified"]))

        mapping.filter_map do |name, claim|
          value = confirmed[claim.to_s]
          [ name.to_s, value ] unless value.nil? || value == ""
        end
      end

      def sign(xml)
        document = XMLSecurity::Document.new(xml)
        document.sign_document(key.private_key, key.certificate, XMLSecurity::Document::RSA_SHA256, XMLSecurity::Document::SHA256)
        document.to_s
      end

      def encode(xml)
        Base64.strict_encode64(xml)
      end

      def identifier
        "_#{SecureRandom.hex(20)}"
      end

      def instant(time)
        time.utc.iso8601
      end
  end
end
