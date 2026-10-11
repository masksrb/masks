module Masks
  module Server
    module SamlIdentity
      class Message
        SIGNATURE_ALGORITHMS = [
          XMLSecurity::Document::RSA_SHA256, XMLSecurity::Document::RSA_SHA384, XMLSecurity::Document::RSA_SHA512
        ].freeze
        IDENTIFIER = /\A[A-Za-z_][\w.-]{0,127}\z/

        attr_reader :client, :id, :relay_state

        def self.read!(request, issuer:)
          new(request, issuer: issuer).tap(&:read!)
        end

        def initialize(request, issuer:)
          @request = request
          @issuer = issuer
          @relay_state = carried("RelayState").presence
        end

        private

          attr_reader :request, :issuer, :xml, :document, :root

          def field
            "SAMLRequest"
          end

          def named
            "#{element.start_with?('A') ? 'an' : 'a'} #{element}"
          end

          def open!
            raw = carried(field).to_s

            raise Refused, "a #{field} is required" if raw.blank?
            raise Refused, "that #{field} is too large" if raw.bytesize > LIMIT

            @xml = decode(raw)
            @document = SamlIdentity.parse!(xml, what: "that #{field}")
            @root = document.root

            raise Refused, "that is not #{named}" unless root&.name == element && root.namespace&.href == PROTOCOL_NS
            raise Refused, "only SAML 2.0 messages are read" unless root["Version"] == "2.0"

            @id = root["ID"].to_s
            raise Refused, "#{named} carries an ID" unless id.match?(IDENTIFIER)
            raise Refused, "#{named} names each ID once" unless document.xpath("//@ID").map(&:value).tally.values.all?(1)

            @client = registered
          end

          def redirect?
            request.get?
          end

          def raw_query
            @raw_query ||= request.query_string.split("&").each_with_object({}) do |pair, held|
              name, value = pair.split("=", 2)
              raise Refused, "#{CGI.unescape(name.to_s)} is sent more than once" if held.key?(CGI.unescape(name.to_s))

              held[CGI.unescape(name.to_s)] = value.to_s
            end
          end

          def carried(name)
            redirect? ? raw_query[name]&.then { |value| CGI.unescape(value) } : request.request_parameters[name]
          end

          def decode(raw)
            bytes = Base64.decode64(raw)
            xml = bytes.lstrip.start_with?("<") ? bytes : inflate(bytes)

            xml.force_encoding(Encoding::UTF_8)

            raise Refused, "that #{field} is not UTF-8" unless xml.valid_encoding?

            xml
          end

          def inflate(bytes)
            inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
            inflated = +""

            inflater.inflate(bytes) do |chunk|
              inflated << chunk
              raise Refused, "that #{field} is too large" if inflated.bytesize > LIMIT
            end

            inflated
          rescue Zlib::Error
            raise Refused, "that #{field} could not be read"
          ensure
            inflater&.close
          end

          def registered
            entity = document.at_xpath("/samlp:#{element}/saml:Issuer", "samlp" => PROTOCOL_NS, "saml" => ASSERTION_NS)&.text.to_s.strip

            raise Refused, "#{named} names its Issuer" if entity.blank?

            Client.saml_for(entity) || raise(Refused, "no application is registered here as #{entity}")
          end

          def timely!
            made = Time.iso8601(root["IssueInstant"].to_s)

            raise Refused, "that #{element} was made too long ago" if made < (LIFETIME + CLOCK_SKEW).ago
            raise Refused, "that #{element} was made in the future" if made > CLOCK_SKEW.from_now
          rescue ArgumentError
            raise Refused, "#{named} says when it was made"
          end

          def addressed!(url)
            destination = root["Destination"].presence

            return if destination.nil? || destination == url

            raise Refused, "that #{element} was sent to #{destination}, not here"
          end

          def signed!(certificate)
            redirect? ? query_signed!(certificate) : document_signed!(certificate)
          end

          def query_signed!(certificate)
            algorithm = CGI.unescape(raw_query["SigAlg"].to_s)

            raise Refused, "a signed redirect carries SigAlg with SHA-256 or stronger" unless SIGNATURE_ALGORITHMS.include?(algorithm)
            raise Refused, "a signed redirect carries a Signature" if raw_query["Signature"].blank?

            signed = OneLogin::RubySaml::Utils.build_query_from_raw_parts(
              type: field, raw_data: raw_query[field], raw_relay_state: raw_query["RelayState"],
              raw_sig_alg: raw_query["SigAlg"]
            )

            verified = OneLogin::RubySaml::Utils.verify_signature(
              cert: certificate, sig_alg: algorithm, signature: CGI.unescape(raw_query["Signature"]), query_string: signed
            )

            raise Refused, "that #{element}'s signature does not verify" unless verified
          rescue OpenSSL::PKey::PKeyError
            raise Refused, "that #{element}'s signature does not verify"
          end

          def document_signed!(certificate)
            signatures = document.xpath("//ds:Signature", "ds" => DSIG_NS)

            raise Refused, "a signed #{element} carries exactly one Signature, its own" unless signatures.one? && signatures.first.parent == root

            reference = signatures.first.at_xpath("ds:SignedInfo/ds:Reference", "ds" => DSIG_NS)&.[]("URI")
            raise Refused, "that signature covers something other than the #{element}" unless reference == "##{id}"

            algorithm = signatures.first.at_xpath("ds:SignedInfo/ds:SignatureMethod", "ds" => DSIG_NS)&.[]("Algorithm")
            raise Refused, "a signed #{element} uses SHA-256 or stronger" unless SIGNATURE_ALGORITHMS.include?(algorithm)

            verified = XMLSecurity::SignedDocument.new(xml).validate_document_with_cert(certificate, true)

            raise Refused, "that #{element}'s signature does not verify" unless verified
          end

          def once!(kind)
            return if Replay.first?(kind, id, within: client.id, expires_in: LIFETIME + (CLOCK_SKEW * 2))

            raise Refused, "that #{element} has already been answered"
          end
      end
    end
  end
end
