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
      {
        "setup" => {
          "token" => self.class.token_required?,
          "minimum" => MINIMUM_PASSWORD
        }
      }
    end

    private

      def claim
        return unless permitted? && valid?

        actor = Actor.new(
          nickname: nickname,
          email: email,
          password: password,
          scopes: Scopes.join(Scopes::STANDARD + [ Scopes::MANAGE ])
        )

        return warn!("invalid-account") unless actor.save

        Verifications.open(actor: actor)

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
        warn! "missing-email" if email.blank?
        warn! "short-password" if password.length < MINIMUM_PASSWORD

        login.warnings.size == before
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
  end
end
