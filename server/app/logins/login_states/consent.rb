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
          "audience" => audience
        }
      }
    end

    def start_over!
      expire! :consent
    end

    def required?
      return false if touched?(:consent)
      return true if request.consent?
      return false if client&.approved?

      !::Consent.covers?(
        actor: actor, client: client, scopes: scopes, audience: audience
      )
    end

    def scopes
      request.scopes_for(actor)
    end

    def audience
      request.audience
    end

    private

      def record
        return refuse!("access_denied", "the person signing in declined") if update(:approve).blank?

        ::Consent.record!(
          actor: actor, client: client, scopes: scopes, audience: audience
        )

        Event.record!(
          Event::CONSENT_GRANTED,
          actor: actor, client: client, scopes: scopes, audience: audience.presence
        )

        factored! :consent, expiry: EXPIRY
      end
  end
end
