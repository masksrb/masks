module Federation
  class Saml < Protocol
    CLOCK_DRIFT = 60.seconds
    METADATA_LIMIT = 512.kilobytes
    NAME_ID = "name_id".freeze
    NAME_ID_FORMATS = SamlIdentity::NAME_ID_FORMATS

    class << self
      def parse_metadata(xml)
        parsed = OneLogin::RubySaml::IdpMetadataParser.new.parse_to_hash(
          xml.to_s,
          sso_binding: [ OneLogin::RubySaml::Utils::BINDINGS[:redirect] ]
        )

        certificates = Array(parsed.dig(:idp_cert_multi, :signing)).presence || Array(parsed[:idp_cert])

        {
          idp_entity_id: parsed[:idp_entity_id],
          idp_sso_url: parsed[:idp_sso_service_url],
          idp_certificates: certificates.compact_blank.map { |one| pem(one) }.join("\n")
        }
      rescue REXML::ParseException, ArgumentError, OpenSSL::X509::CertificateError => e
        raise Provider::Untrusted, "that metadata could not be read: #{e.message.lines.first.to_s.strip}"
      end

      def pem(certificate)
        OneLogin::RubySaml::Utils.format_cert(certificate.to_s.strip)
      end
    end

    def start(callback:)
      handoff = { "state" => SecureRandom.urlsafe_base64(STATE_BYTES) }
      request = OneLogin::RubySaml::Authrequest.new

      location = request.create(settings(callback), RelayState: handoff["state"])

      [ location, handoff.merge("request_id" => request.request_id) ]
    end

    def finish(params, handoff:, callback:)
      relay = params["RelayState"].presence || params["state"]

      unless relay.present? && ActiveSupport::SecurityUtils.secure_compare(relay.to_s, handoff["state"].to_s)
        raise Provider::Untrusted, "the relay state did not match this browser"
      end

      raise Provider::Refused, "#{provider.name} returned no SAML response" if params["SAMLResponse"].blank?

      response = OneLogin::RubySaml::Response.new(
        params["SAMLResponse"].to_s,
        settings: settings(callback),
        matches_request_id: handoff["request_id"].to_s,
        allowed_clock_drift: CLOCK_DRIFT
      )

      unless response.is_valid?(true)
        raise Provider::Untrusted, "#{provider.name} sent an assertion this server could not trust: #{response.errors.first}"
      end

      identity = normalize(response)

      raise Provider::Untrusted, "#{provider.name} named nobody in that assertion" if identity["sub"].blank?

      identity
    end

    def entity_id
      "#{Current.origin}/login/provider/#{provider.key}/metadata"
    end

    def metadata(callback:)
      OneLogin::RubySaml::Metadata.new.generate(settings(callback), true)
    end

    private

      def settings(callback)
        OneLogin::RubySaml::Settings.new.tap do |settings|
          settings.sp_entity_id = entity_id
          settings.assertion_consumer_service_url = callback
          settings.idp_entity_id = provider.idp_entity_id
          settings.idp_sso_service_url = provider.idp_sso_url
          settings.idp_cert_multi = { signing: provider.idp_certificate_list, encryption: [] }
          settings.name_identifier_format = provider.name_id_format.presence
          settings.soft = true
          settings.security[:want_assertions_signed] = true
          settings.security[:strict_audience_validation] = true
          settings.security[:digest_method] = XMLSecurity::Document::SHA256
          settings.security[:signature_method] = XMLSecurity::Document::RSA_SHA256
        end
      end

      def normalize(response)
        map = provider.claim_map
        attributes = response.attributes

        held = Provider::MAPPED_CLAIMS.index_with do |claim|
          next if claim == "email_verified"

          attribute(attributes, map.fetch(claim, claim))
        end

        held["sub"] = map["sub"] == NAME_ID ? response.name_id.to_s.presence : attribute(attributes, map["sub"])&.to_s.presence
        held["email"] = held["email"].to_s.strip.downcase.presence

        held.compact
      end

      def attribute(attributes, name)
        value = attributes[name.to_s]

        value.is_a?(Array) ? value.first : value
      end
  end
end
