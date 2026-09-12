module LoginStates
  class Passkey < LoginState
    FIRST_EXPIRY = 12.hours
    SECOND_EXPIRY = 12.hours
    HELD = "passkey_challenge".freeze

    accepts :passkey

    handles "passkey:challenge" do
      offer
    end

    handles "passkey:verify" do
      verify
    end

    def enabled?
      ::Passkey.exists?
    end

    def as_json
      { "passkey" => { "offered" => true }.merge(challenge_json) }
    end

    def start_over!
      login.store.delete(HELD)
    end

    private

      def challenge_json
        held = login.store[HELD]
        return {} if held.blank?

        { "options" => held["options"] }
      end

      def offer
        options = relying_party.authentication_options(login.actor)

        login.store[HELD] = { "challenge" => options.challenge, "options" => options.as_json }
      end

      def verify
        held = login.store[HELD]
        return warn!("passkey-expired") if held.blank?

        presented = update(:passkey)
        return warn!("invalid-passkey") if presented.blank?

        settle(held["challenge"], JSON.parse(presented))
      ensure
        login.store.delete(HELD)
      end

      def settle(challenge, response)
        passkey = ::Passkey.find_by(external_id: response["id"])
        if passkey.nil?
          refused! "passkey"
          return warn!("invalid-passkey")
        end

        credential = relying_party.verify_authentication(response, challenge, passkey)
        verified = !!credential.response.authenticator_data.user_verified?

        if passkey.cloned?(credential.sign_count)
          Event.record!(
            Event::LOGIN_REFUSED,
            actor: passkey.actor, by: nil, factor: "passkey", cloned: true
          )
          return warn!("invalid-passkey")
        end

        passkey.used!(credential.sign_count, user_verified: verified)

        accept(passkey, verified)
      rescue WebAuthn::Error, JSON::ParserError
        refused! "passkey"
        warn! "invalid-passkey"
      end

      def accept(passkey, verified)
        login.identifier = passkey.actor.identifier
        login.actor = passkey.actor

        factored! :first_factor, expiry: FIRST_EXPIRY
        login.noted! "swk"

        return unless verified

        factored! :second_factor, expiry: SECOND_EXPIRY
        login.noted! "user", "mfa"
      end

      def relying_party
        RelyingParty.for(tenant, Current.origin)
      end
  end
end
