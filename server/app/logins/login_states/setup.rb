module LoginStates
  class Setup < LoginState
    EXPIRY = 12.hours
    MINIMUM_PASSWORD = 8

    accepts :nickname, :email, :password, :token

    class << self
      def token
        Rails.configuration.masks.setup_token
      end

      def token_required?
        token.present?
      end
    end

    handles "setup" do
      claim
    end

    prompts "setup" do
      true
    end

    def reload!
      @pending = !Actor.exists?
    end

    def enabled?
      @pending.present?
    end

    def as_json
      { "setup" => { "token" => self.class.token_required? } }
    end

    private

      def claim
        return unless permitted? && valid?

        actor = Actor.new(
          nickname: nickname,
          email: update(:email).presence,
          password: password,
          scopes: Scopes.join(Scopes::STANDARD),
          email_verified_at: (Time.current if update(:email).present?)
        )

        return warn!("invalid-account") unless actor.save

        login.identifier = actor.nickname
        login.actor = actor
        factored! :first_factor, expiry: EXPIRY
        @pending = false
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

      def valid?
        before = login.warnings.size

        warn! "missing-nickname" if nickname.blank?
        warn! "short-password" if password.length < MINIMUM_PASSWORD

        login.warnings.size == before
      end

      def nickname
        update(:nickname).to_s.strip
      end

      def password
        update(:password).to_s
      end
  end
end
