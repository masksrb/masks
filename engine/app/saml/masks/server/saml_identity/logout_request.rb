module Masks
  module Server
    module SamlIdentity
      class LogoutRequest < Message
        NAMES = { "samlp" => PROTOCOL_NS, "saml" => ASSERTION_NS }.freeze

        attr_reader :name_id, :session_indexes

        def read!
          open!
          timely!
          addressed!(SamlIdentity.slo_url(issuer))
          answerable!
          signed!(client.saml_x509_certificate || raise(Refused, "#{client.name} has no certificate to check its logout requests against"))
          current!
          @name_id = subject!
          @session_indexes = document.xpath("/samlp:LogoutRequest/samlp:SessionIndex", NAMES).map { |index| index.text.strip }.compact_blank
          once!("saml-logout")

          self
        end

        private

          def element
            "LogoutRequest"
          end

          def answerable!
            raise Refused, "#{client.name} has no single logout URL to answer at" if client.saml_slo_url.blank?
          end

          def current!
            return if root["NotOnOrAfter"].blank?

            raise Refused, "that LogoutRequest has expired" if Time.iso8601(root["NotOnOrAfter"]) <= CLOCK_SKEW.ago
          rescue ArgumentError
            raise Refused, "that LogoutRequest's NotOnOrAfter is not a time"
          end

          def subject!
            named = document.at_xpath("/samlp:LogoutRequest/saml:NameID", NAMES)&.text.to_s.strip

            raise Refused, "a LogoutRequest names who is signing out with a NameID" if named.blank?

            named
          end
      end
    end
  end
end
