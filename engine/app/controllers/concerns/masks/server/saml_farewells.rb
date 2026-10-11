module Masks
  module Server
    module SamlFarewells
      extend ActiveSupport::Concern

      private

        def farewell(departing, finish:)
          proceed(SamlIdentity::Farewells.new(departing.map(&:id), finish))
        end

        def proceed(farewells)
          sign_off = farewells.advance(issuer)

          return post_saml(sign_off.client, sign_off.destination, "SAMLRequest", sign_off.encoded, leaving: true) if sign_off

          finish_farewells(farewells.finish)
        end

        def finish_farewells(held)
          return redirect_to(held["redirect"], allow_other_host: true) if held["redirect"]

          client = Client.speaking(SamlIdentity::PROTOCOL).find_by(client_id: held["client_id"])

          return redirect_to(login_path) if client.nil? || client.saml_slo_url.blank?

          answer = SamlIdentity::Response.new(
            issuer: issuer, client: client, destination: client.saml_slo_url, in_response_to: held["in_response_to"]
          )

          encoded = held["known"] ? answer.logout : answer.logout(SamlIdentity::REQUESTER, SamlIdentity::UNKNOWN_PRINCIPAL, "nobody by that NameID is signed in to it here")

          post_saml(client, client.saml_slo_url, "SAMLResponse", encoded, relay_state: held["relay_state"], leaving: true)
        end

        def post_saml(client, destination, field, encoded, relay_state: nil, leaving: false)
          @client = client
          @destination = destination
          @saml_field = field
          @saml_message = encoded
          @relay_state = relay_state
          @leaving = leaving
          @script_nonce = SecureRandom.base64(16)

          response.headers["Content-Security-Policy"] =
            "default-src 'self'; script-src 'nonce-#{@script_nonce}'; frame-ancestors 'none'"
          response.headers["Cache-Control"] = "no-store"

          render "masks/server/saml/post"
        end
    end
  end
end
