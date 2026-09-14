module SamlIdentity
  class Request
    SIGNATURE_ALGORITHMS = {
      "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256" => "SHA256",
      "http://www.w3.org/2001/04/xmldsig-more#rsa-sha384" => "SHA384",
      "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512" => "SHA512"
    }.freeze

    attr_reader :client, :id, :acs_url, :relay_state, :name_id_format, :force_authn, :passive

    def self.read!(request, issuer:)
      new(request, issuer: issuer).tap(&:read!)
    end

    def initialize(request, issuer:)
      @request = request
      @issuer = issuer
      @relay_state = request.params["RelayState"].presence
    end

    def read!
      raw = request.params["SAMLRequest"].to_s

      raise Refused, "a SAMLRequest is required" if raw.blank?
      raise Refused, "that SAMLRequest is too large" if raw.bytesize > LIMIT

      @xml = decode(raw)
      document = parse(@xml)
      root = document.root

      raise Refused, "that is not an AuthnRequest" unless root&.name == "AuthnRequest" && root.namespace&.href == PROTOCOL_NS
      raise Refused, "only SAML 2.0 requests are read" unless root["Version"] == "2.0"

      @id = root["ID"].to_s
      raise Refused, "an AuthnRequest carries an ID" unless @id.match?(/\A[A-Za-z_][\w.-]{0,127}\z/)
      raise Refused, "an AuthnRequest names each ID once" unless document.xpath("//@ID").map(&:value).tally.values.all?(1)

      @client = registered(document)
      timely!(root)
      addressed!(root)
      signed!(document)
      @acs_url = consumer!(root)
      @name_id_format = format!(document)
      @force_authn = root["ForceAuthn"] == "true"
      @passive = root["IsPassive"] == "true"
      once!

      self
    end

    private

      attr_reader :request, :issuer, :xml

      def redirect?
        request.get?
      end

      def decode(raw)
        bytes = Base64.decode64(raw)
        xml = bytes.lstrip.start_with?("<") ? bytes : inflate(bytes)

        xml.force_encoding(Encoding::UTF_8)

        raise Refused, "that SAMLRequest is not UTF-8" unless xml.valid_encoding?

        xml
      end

      def inflate(bytes)
        inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
        inflated = inflater.inflate(bytes)

        raise Refused, "that SAMLRequest is too large" if inflated.bytesize > LIMIT

        inflated
      rescue Zlib::Error
        raise Refused, "that SAMLRequest could not be read"
      ensure
        inflater&.close
      end

      def parse(xml)
        raise Refused, "a SAMLRequest may not declare a document type" if xml.match?(/<!DOCTYPE/i)

        Nokogiri::XML(xml) { |config| config.strict.nonet }
      rescue Nokogiri::XML::SyntaxError
        raise Refused, "that SAMLRequest is not well-formed XML"
      end

      def registered(document)
        entity = document.at_xpath("/samlp:AuthnRequest/saml:Issuer", "samlp" => PROTOCOL_NS, "saml" => ASSERTION_NS)&.text.to_s.strip

        raise Refused, "an AuthnRequest names its Issuer" if entity.blank?

        Client.saml_for(entity) || raise(Refused, "no application is registered here as #{entity}")
      end

      def timely!(root)
        made = Time.iso8601(root["IssueInstant"].to_s)

        raise Refused, "that AuthnRequest was made too long ago" if made < (LIFETIME + CLOCK_SKEW).ago
        raise Refused, "that AuthnRequest was made in the future" if made > CLOCK_SKEW.from_now
      rescue ArgumentError
        raise Refused, "an AuthnRequest says when it was made"
      end

      def addressed!(root)
        destination = root["Destination"].presence

        return if destination.nil? || destination == SamlIdentity.sso_url(issuer)

        raise Refused, "that AuthnRequest was sent to #{destination}, not here"
      end

      def consumer!(root)
        binding = root["ProtocolBinding"].presence
        raise Refused, "responses are only sent with HTTP-POST" if binding && binding != POST_BINDING
        raise Refused, "an AssertionConsumerServiceIndex is not read; name the URL" if root["AssertionConsumerServiceIndex"].present?

        wanted = root["AssertionConsumerServiceURL"].presence

        return client.redirect_uris.first if wanted.nil?
        return wanted if client.redirect_uri?(wanted)

        raise Refused, "#{wanted} is not an assertion consumer service registered for #{client.name}"
      end

      def format!(document)
        asked = document.at_xpath("/samlp:AuthnRequest/samlp:NameIDPolicy", "samlp" => PROTOCOL_NS)&.[]("Format").presence

        return client.saml_name_id_format.presence || PERSISTENT if asked.nil? || asked == UNSPECIFIED
        return asked if NAME_ID_FORMATS.include?(asked)

        raise Refused, "#{asked} is not a NameID format masks issues"
      end

      def signed!(document)
        return unless client.saml_requests_signed?

        certificate = client.saml_x509_certificate || raise(Refused, "#{client.name} has no certificate to check its requests against")

        redirect? ? query_signed!(certificate) : document_signed!(document, certificate)
      end

      def query_signed!(certificate)
        pairs = request.query_string.split("&").to_h { |pair| pair.split("=", 2) }
        algorithm = SIGNATURE_ALGORITHMS[CGI.unescape(pairs["SigAlg"].to_s)]

        raise Refused, "a signed redirect carries SigAlg with SHA-256 or stronger" if algorithm.nil?
        raise Refused, "a signed redirect carries a Signature" if pairs["Signature"].blank?

        signed = [ "SAMLRequest=#{pairs['SAMLRequest']}", ("RelayState=#{pairs['RelayState']}" if pairs.key?("RelayState")),
                   "SigAlg=#{pairs['SigAlg']}" ].compact.join("&")
        signature = Base64.decode64(CGI.unescape(pairs["Signature"]))

        return if certificate.public_key.verify(OpenSSL::Digest.new(algorithm), signature, signed)

        raise Refused, "that AuthnRequest's signature does not verify"
      rescue OpenSSL::PKey::PKeyError
        raise Refused, "that AuthnRequest's signature does not verify"
      end

      def document_signed!(document, certificate)
        signatures = document.xpath("/samlp:AuthnRequest/ds:Signature", "samlp" => PROTOCOL_NS, "ds" => DSIG_NS)

        raise Refused, "a signed AuthnRequest carries one Signature of its own" unless signatures.one?

        reference = signatures.first.at_xpath("ds:SignedInfo/ds:Reference", "ds" => DSIG_NS)&.[]("URI")
        raise Refused, "that signature covers something other than the request" unless reference == "##{id}"

        algorithm = signatures.first.at_xpath("ds:SignedInfo/ds:SignatureMethod", "ds" => DSIG_NS)&.[]("Algorithm")
        raise Refused, "a signed AuthnRequest uses SHA-256 or stronger" unless SIGNATURE_ALGORITHMS.key?(algorithm)

        verified = XMLSecurity::SignedDocument.new(xml).validate_document_with_cert(certificate, true)

        raise Refused, "that AuthnRequest's signature does not verify" unless verified
      end

      def once!
        key = "saml-request:#{client.tenant_id}:#{client.id}:#{Digest::SHA256.hexdigest(id)}"

        return if Rails.cache.write(key, true, expires_in: LIFETIME + (CLOCK_SKEW * 2), unless_exist: true)

        raise Refused, "that AuthnRequest has already been answered"
      end
  end
end
