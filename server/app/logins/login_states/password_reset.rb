module LoginStates
  class PasswordReset < LoginState
    EXPIRY = 12.hours
    MINIMUM_PASSWORD = Actor::MINIMUM_PASSWORD
    HELD = "reset".freeze
    SENT = "reset-sent".freeze

    accepts :password

    handles "forgot-password" do
      open
    end

    handles "reset-password" do
      settle
    end

    prompts "reset-password" do
      reset.present?
    end

    def reload!
      @loaded = false
      @reset = nil
    end

    def as_json
      held = reset
      return {} if held.nil?

      {
        "reset" => {
          "nickname" => held.actor.nickname,
          "minimum" => MINIMUM_PASSWORD
        }
      }
    end

    def start_over!
      login.store.delete(HELD)
      reload!
    end

    def reset
      return @reset if @loaded

      @loaded = true
      secret = login.store[HELD]
      @reset = secret.present? ? ::PasswordReset.redeem(secret) : nil
    end

    private

      def open
        return warn!("missing-identifier") if login.identifier.blank?
        return warn!("no-mailer") unless ActorMailer.deliverable?

        Recoveries.request(identifier: login.identifier)

        warn! SENT
      end

      def settle
        return warn!("reset-expired") if reset.nil?
        return warn!("short-password") if password.length < MINIMUM_PASSWORD

        actor = ::PasswordReset.settle!(login.store[HELD], password)
        return warn!("reset-expired") if actor.nil?

        login.store.delete(HELD)
        reload!
        login.identifier = actor.nickname
        login.actor = actor
        factored! :first_factor, expiry: EXPIRY
      end

      def password
        update(:password).to_s
      end
  end
end
