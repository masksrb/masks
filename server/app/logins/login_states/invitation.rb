module LoginStates
  class Invitation < LoginState
    EXPIRY = 12.hours
    MINIMUM_PASSWORD = Actor::MINIMUM_PASSWORD
    HELD = "invitation".freeze

    accepts :password

    handles "accept-invitation" do
      accept
    end

    prompts "accept-invitation" do
      invitation.present?
    end

    def reload!
      @loaded = false
      @invitation = nil
    end

    def enabled?
      invitation.present?
    end

    def as_json
      held = invitation
      return {} if held.nil?

      {
        "invitation" => {
          "nickname" => held.actor.identifier,
          "email" => held.actor.email,
          "invitedBy" => held.opened_by&.identifier,
          "minimum" => MINIMUM_PASSWORD
        }
      }
    end

    def start_over!
      login.store.delete(HELD)
      reload!
    end

    def invitation
      return @invitation if @loaded

      @loaded = true
      secret = login.store[HELD]
      @invitation = secret.present? ? ::Invitation.redeem(secret) : nil
    end

    private

      def accept
        return warn!("invitation-expired") if invitation.nil?
        return warn!("short-password") if password.length < MINIMUM_PASSWORD

        actor = ::Invitation.accept!(login.store[HELD], password)
        return warn!("invitation-expired") if actor.nil?

        Event.record!(Event::INVITATION_ACCEPTED, actor: actor)

        login.store.delete(HELD)
        reload!
        login.identifier = actor.identifier
        login.actor = actor
        factored! :first_factor, expiry: EXPIRY
      end

      def password
        update(:password).to_s
      end
  end
end
