module LoginStates
  class Setup < LoginState
    EXPIRY = 12.hours
    WINDOW = 30.minutes
    HELD = "setup_identity".freeze
    CONFIGURING = "setup_configuring".freeze
    MINIMUM_PASSWORD = Actor::MINIMUM_PASSWORD
    ANYTHING = "anything".freeze
    BOUNDED = "bounded".freeze
    REGISTRATIONS = [ ANYTHING, BOUNDED ].freeze

    accepts :nickname, :email, :name, :password, :password_confirmation, :token,
            :named_by, :called, :registration, :registration_scopes

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
      configure
    end

    handles "setup-edit" do
      edit
    end

    handles "setup-configure" do
      configure
    end

    prompts "setup" do
      !configuring? && (held.blank? || held["editing"])
    end

    prompts "setup-password" do
      !configuring?
    end

    prompts "setup-configure" do
      configuring?
    end

    def reload!
      @pending = !Actor.exists?
    end

    def enabled?
      @pending.present? || configuring?
    end

    def as_json
      {
        "setup" => {
          "token" => self.class.token_required?,
          "minimum" => MINIMUM_PASSWORD,
          "nickname" => held["nickname"],
          "email" => held["email"],
          "name" => held["name"],
          "names" => Tenant::NAMES,
          "namedBy" => tenant&.named_by,
          "called" => tenant&.name,
          "registration" => BOUNDED,
          "registrationScopes" => Scopes.join(tenant&.dynamic_client_ceiling || Scopes::STANDARD),
          "mails" => ActorMailer.deliverable?
        }
      }
    end

    def start_over!
      login.store.delete(HELD)
      login.store.delete(CONFIGURING)
    end

    def cleanup!
      return if held.blank?

      login.store.delete(HELD) if held["expires_at"].to_i <= Time.current.to_i
    end

    private

      def held
        login.store[HELD] || {}
      end

      def configuring?
        login.store[CONFIGURING].present?
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
          "name" => name,
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
          name: held["name"],
          password: password,
          scopes: Scopes.join(Scopes::STANDARD + [ Scopes::MANAGE ])
        )

        return warn!("invalid-account") unless actor.save

        Event.record!(Event::ACCOUNT_CREATED, actor: actor, first_run: true)

        Verifications.open(actor: actor)

        login.store.delete(HELD)
        login.identifier = actor.identifier
        login.actor = actor
        factored! :first_factor, expiry: EXPIRY
        login.store[CONFIGURING] = true unless tenant.names_pinned?
        @pending = false
      end

      def configure
        return unless configuring?

        wanted = update(:named_by).to_s
        asked = login.event == "setup-configure"

        return if wanted.blank? && !asked
        return warn!("unknown-name-rule") unless Tenant::NAMES.include?(wanted)

        tenant.named_by = wanted
        tenant.name = called if called.present?
        tenant.dynamic_client_scopes = ceiling

        return warn!("invalid-configuration") unless tenant.save

        login.store.delete(CONFIGURING)
      end

      def called
        update(:called).to_s.strip
      end

      def ceiling
        return nil unless update(:registration).to_s == BOUNDED

        offered = Scopes.list(update(:registration_scopes)) - Scopes.reserved(update(:registration_scopes))

        Scopes.join(offered).presence
      end

      def kept
        before = login.warnings.size

        yield

        login.warnings.size == before
      end

      def identifying?
        updates.key?("nickname") || updates.key?("email") || updates.key?("name")
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

      def name
        update(:name).to_s.strip.presence
      end

      def password
        update(:password).to_s
      end

      def password_confirmation
        update(:password_confirmation).to_s
      end
  end
end
