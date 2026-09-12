module LoginStates
  class Setup < LoginState
    EXPIRY = 12.hours
    WINDOW = 30.minutes
    HELD = "setup_identity".freeze
    MINIMUM_PASSWORD = Actor::MINIMUM_PASSWORD

    accepts :nickname, :email, :password, :password_confirmation, :token

    class << self
      def token
        Rails.configuration.masks.setup_token
      end

      def token_required?
        token.present?
      end
    end

    handles "setup" do
      hold
      claim
    end

    handles "setup-edit" do
      edit
    end

    prompts "setup" do
      held.blank? || held["editing"]
    end

    prompts "setup-confirm" do
      true
    end

    def reload!
      @pending = !Actor.exists?
    end

    def enabled?
      @pending.present?
    end

    def as_json
      {
        "setup" => {
          "token" => self.class.token_required?,
          "minimum" => MINIMUM_PASSWORD,
          "nickname" => held["nickname"],
          "email" => held["email"]
        }
      }
    end

    def start_over!
      login.store.delete(HELD)
    end

    def cleanup!
      return if held.blank?

      login.store.delete(HELD) if held["expires_at"].to_i <= Time.current.to_i
    end

    private

      def held
        login.store[HELD] || {}
      end

      def hold
        return if held.present? && !identifying?
        return unless permitted?

        identified = kept do
          warn! "missing-nickname" if nickname.blank?
          warn! "missing-email" if email.blank?
        end

        return unless identified

        login.store[HELD] = {
          "nickname" => nickname,
          "email" => email,
          "expires_at" => (Time.current + WINDOW).to_i
        }
      end

      def edit
        return if held.blank?

        login.store[HELD] = held.merge("editing" => true)
      end

      def claim
        return if held.blank? || held["editing"] || !crediting?

        credited = kept do
          warn! "short-password" if password.length < MINIMUM_PASSWORD
          warn! "mismatched-password" if password != password_confirmation
        end

        return unless credited

        actor = Actor.new(
          nickname: held["nickname"],
          email: held["email"],
          password: password,
          scopes: Scopes.join(Scopes::STANDARD + [ Scopes::MANAGE ])
        )

        return warn!("invalid-account") unless actor.save

        Event.record!(Event::ACCOUNT_CREATED, actor: actor, first_run: true)

        Verifications.open(actor: actor)

        login.store.delete(HELD)
        login.identifier = actor.nickname
        login.actor = actor
        factored! :first_factor, expiry: EXPIRY
        @pending = false
      end

      def kept
        before = login.warnings.size

        yield

        login.warnings.size == before
      end

      def identifying?
        updates.key?("nickname") || updates.key?("email")
      end

      def crediting?
        updates.key?("password") || updates.key?("password_confirmation")
      end

      def permitted?
        return true unless self.class.token_required?

        given = update(:token).to_s
        expected = self.class.token

        return true if given.present? &&
                       ActiveSupport::SecurityUtils.secure_compare(given, expected)

        warn! "invalid-setup-token"
        false
      end

      def nickname
        update(:nickname).to_s.strip
      end

      def email
        update(:email).to_s.strip.presence
      end

      def password
        update(:password).to_s
      end

      def password_confirmation
        update(:password_confirmation).to_s
      end
  end
end
