module Masks
  module Server
    class Client
      module SamlApplication
        extend ActiveSupport::Concern

        included do
          validates :saml_entity_id, uniqueness: { scope: :tenant_id }, allow_nil: true
          validate :saml_is_described, if: :saml?

          normalizes :saml_entity_id, :saml_slo_url, with: ->(value) { value.to_s.strip.presence }
        end

        class_methods do
          def saml_for(entity_id)
            speaking(SamlIdentity::PROTOCOL).find_by(saml_entity_id: entity_id.to_s)
          end
        end

        def saml?
          protocol == SamlIdentity::PROTOCOL
        end

        def saml_x509_certificate
          return nil if saml_certificate.blank?

          OpenSSL::X509::Certificate.new(OneLogin::RubySaml::Utils.format_cert(saml_certificate.to_s.strip))
        rescue OpenSSL::X509::CertificateError
          nil
        end

        private

          def saml_is_described
            errors.add(:saml_entity_id, "is required for a SAML application") if saml_entity_id.blank?
            errors.add(:grant_types, "are not used by a SAML application") if grant_types.any?
            errors.add(:token_endpoint_auth_method, "is none for a SAML application") unless public?
            errors.add(:saml_certificate, "is not a certificate masks can read") if saml_certificate.present? && saml_x509_certificate.nil?
            errors.add(:saml_certificate, "is required to check signed requests") if saml_requests_signed? && saml_certificate.blank?
            saml_slo_url&.then { |url| web_uri_refusal(url, fetched: true) }&.then { |refusal| errors.add(:saml_slo_url, refusal) }

            if saml_name_id_format.present? && !SamlIdentity::NAME_ID_FORMATS.include?(saml_name_id_format)
              errors.add(:saml_name_id_format, "is not one masks issues")
            end

            unless saml_attributes.is_a?(Hash) && saml_attributes.all? { |name, claim| name.to_s.match?(/\A[\w:.\/-]{1,256}\z/) && claim.is_a?(String) }
              errors.add(:saml_attributes, "map attribute names to claim names")
            end
          end
      end
    end
  end
end
