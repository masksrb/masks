module Masks
  module Server
    module SamlIdentity
      class LogoutReply < Message
        attr_reader :in_response_to

        def read!
          open!
          timely!
          addressed!(SamlIdentity.slo_url(issuer))
          client.saml_x509_certificate&.then { |certificate| signed!(certificate) }
          @in_response_to = root["InResponseTo"].to_s

          raise Refused, "a LogoutResponse answers a request masks sent" unless in_response_to.match?(IDENTIFIER)

          self
        end

        private

          def field
            "SAMLResponse"
          end

          def element
            "LogoutResponse"
          end
      end
    end
  end
end
