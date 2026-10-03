module Masks
  module Server
    module LoginStates
      class Consent < LoginState
        EXPIRY = 1.hour

        accepts :approve

        def enabled?
          request.present?
        end

        handles "consent" do
          record
        end

        handles "decline" do
          refuse!("access_denied", "the person signing in declined")
        end

        prompts "consent" do
          required?
        end

        def as_json
          return {} unless required?

          {
            "consent" => {
              "scopes" => ResourceMetadata.describe(audience, scopes),
              "audience" => audience,
              "details" => details&.described
            }.compact
          }
        end

        def start_over!
          expire! :consent
        end

        def required?
          return false if consented_here?
          return true if request.consent?
          return true if login.state("delegation").undelegated.any?
          return false if details.nil? && client && !client.consent_required?

          !Masks::Server::Consent.covers?(
            actor: actor, client: client, scopes: scopes, audience: audience, details: details
          )
        end

        def scopes
          request.scopes_for(actor)
        end

        def audience
          request.audience
        end

        def details
          return @details if defined?(@details)

          @details = AuthorizationDetails.parse(request.authorization_details)
        end

        def consented_here?
          touched?(:consent) && login.factors.dig("consent", "rid") == login.rid.to_s
        end

        private

          def record
            return refuse!("access_denied", "the person signing in declined") if update(:approve).blank?

            Masks::Server::Consent.record!(
              actor: actor, client: client, scopes: scopes, audience: audience, details: details
            )

            Event.record!(
              Event::CONSENT_GRANTED,
              actor: actor, client: client, scopes: scopes, audience: audience.presence,
              authorization_details: details&.types
            )

            factored!(:consent, expiry: EXPIRY)["rid"] = login.rid.to_s
          end
      end
    end
  end
end
