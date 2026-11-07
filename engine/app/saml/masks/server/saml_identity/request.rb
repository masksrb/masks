module Masks
  module Server
    module SamlIdentity
      class Request < Message
        attr_reader :acs_url, :name_id_format, :force_authn, :passive

        def read!
          open!
          timely!
          addressed!(SamlIdentity.sso_url(issuer))
          vouched!
          @acs_url = consumer!
          @name_id_format = format!
          @force_authn = root["ForceAuthn"] == "true"
          @passive = root["IsPassive"] == "true"
          once!("saml-request")

          self
        end

        private

          def element
            "AuthnRequest"
          end

          def vouched!
            return unless client.saml_requests_signed?

            signed!(client.saml_x509_certificate || raise(Refused, "#{client.name} has no certificate to check its requests against"))
          end

          def consumer!
            binding = root["ProtocolBinding"].presence
            raise Refused, "responses are only sent with HTTP-POST" if binding && binding != POST_BINDING
            raise Refused, "an AssertionConsumerServiceIndex is not read; name the URL" if root["AssertionConsumerServiceIndex"].present?

            wanted = root["AssertionConsumerServiceURL"].presence

            return client.redirect_uris.first if wanted.nil?
            return wanted if client.redirect_uri?(wanted)

            raise Refused, "#{wanted} is not an assertion consumer service registered for #{client.name}"
          end

          def format!
            asked = document.at_xpath("/samlp:AuthnRequest/samlp:NameIDPolicy", "samlp" => PROTOCOL_NS)&.[]("Format").presence

            return client.saml_name_id_format.presence || PERSISTENT if asked.nil? || asked == UNSPECIFIED
            return asked if NAME_ID_FORMATS.include?(asked)

            raise Refused, "#{asked} is not a NameID format masks issues"
          end
      end
    end
  end
end
