module LoginStates
  class Signup < LoginState
    EXPIRY = 12.hours
    WINDOW = 30.minutes
    HELD = "signup".freeze
    SIGNED_UP = "signed_up".freeze
    FIRST_RUN_STEPS = %w[identification credentials configuration].freeze
    STEPS = %w[identification credentials].freeze

    accepts :nickname, :email, :name, :phone, :password, :password_confirmation, :token

    class << self
      def token
        Rails.configuration.masks.setup_token
      end

      def token_required?
        token.present?
      end

      def steps(first_run, policy = nil)
        return FIRST_RUN_STEPS if first_run

        confirming = policy && (policy.confirmation != SignInPolicy::NONE || policy.email_verified || policy.phone_verified)

        confirming ? STEPS + [ "confirmation" ] : STEPS
      end
    end

    handles "signup", limit: :verifying do
      hold
      claim
    end

    handles "signup-edit" do
      edit
    end

    prompts "signup" do
      held.blank? || held["editing"]
    end

    prompts "signup-password" do
      true
    end

    def enabled?
      return false if login.first_factored?

      login.first_run? || open_to?(login.identifier)
    end

    def as_json
      policy = login.policy

      {
        "signup" => {
          "token" => login.first_run? && self.class.token_required?,
          "minimum" => policy.password_minimum,
          "asks" => { "nickname" => policy.nickname, "email" => policy.email, "phone" => policy.phone },
          "nickname" => held.fetch("nickname") { suggested("nickname") },
          "email" => held.fetch("email") { suggested("email") },
          "name" => held["name"],
          "phone" => held["phone"]
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

      def open_to?(identifier)
        policy = login.policy

        return false unless policy.signup && policy.first_factor?(:password)
        return false if identifier.blank? || located?(identifier)

        !identifier.include?("@") || policy.admits?(identifier)
      end

      def located?(identifier)
        @located ||= {}
        @located.fetch(identifier) { @located[identifier] = ::Actor.locate(identifier).present? }
      end

      def suggested(field)
        return nil if login.identifier.blank?

        (field == "email") == login.identifier.include?("@") ? login.identifier : nil
      end

      def hold
        return if held.present? && !held["editing"] && !identifying?
        return unless permitted?

        values = %w[nickname email name phone].to_h do |field|
          [ field, ::Actor.normalize_value_for(field.to_sym, update(field)) ]
        end

        return unless described?(values)

        login.store[HELD] = values.merge("expires_at" => (Time.current + WINDOW).to_i)
      end

      def described?(values)
        policy = login.policy

        kept do
          %w[nickname email phone].each do |field|
            warn! "missing-#{field}", field: field if policy.requires?(field) && values[field].blank?
          end

          warn! "missing-identifier" if values["nickname"].blank? && values["email"].blank?
          warn! "invalid-phone", field: "phone" if values["phone"].present? && Adapters::Sms.number(values["phone"]).nil?
          warn! "signup-domain-refused", field: "email" if values["email"].present? && !policy.admits?(values["email"])
        end
      end

      def edit
        return if held.blank?

        login.store[HELD] = held.merge("editing" => true)
      end

      def claim
        return if held.blank? || held["editing"] || !crediting?

        refusal = Passwords.refusal(password, login.policy)

        credited = kept do
          warn! refusal, field: "password" if refusal
          warn! "mismatched-password", field: "password_confirmation" if password != update(:password_confirmation).to_s
        end

        return unless credited

        actor = create

        return if actor.nil?

        Event.record!(Event::ACCOUNT_CREATED, actor: actor, first_run: @first_run,
                                              signup: !@first_run, policy: login.policy.key)

        Verifications.open(actor: actor) unless !@first_run && login.policy.confirmation == SignInPolicy::CODE
        Confirmations.request_approval(actor) if actor.pending_approval_at.present?

        login.store.delete(HELD)
        login.identifier = actor.identifier
        login.actor = actor
        login.first_run!
        factored! :first_factor, expiry: EXPIRY
        login.noted! "pwd"
        login.store[SIGNED_UP] = { "first_run" => @first_run, "expires_at" => (Time.current + EXPIRY).to_i }
        login.store[Configure::HELD] = true if @first_run
      end

      def create
        ::Actor.transaction do
          ::Tenant.where(id: tenant.id).lock.pick(:id)

          @first_run = !::Actor.exists?
          login.first_run! unless @first_run

          unless @first_run || open_to?(held["email"] || held["nickname"])
            warn! "invalid-account"
            raise ActiveRecord::Rollback
          end

          actor = ::Actor.new(
            nickname: held["nickname"],
            email: held["email"],
            name: held["name"],
            phone: held["phone"],
            password: password,
            signed_up_at: Time.current,
            pending_approval_at: !@first_run && login.policy.confirmation == SignInPolicy::APPROVAL ? Time.current : nil,
            scopes: Scopes.join(@first_run ? Scopes::STANDARD + [ Scopes::MANAGE ] : login.policy.signup_scope_list)
          )

          unless actor.save
            warn! "invalid-account"
            raise ActiveRecord::Rollback
          end

          actor
        end
      end

      def kept
        before = login.warnings.size

        yield

        login.warnings.size == before
      end

      def identifying?
        %w[nickname email name phone].any? { |field| updates.key?(field) }
      end

      def crediting?
        updates.key?("password") || updates.key?("password_confirmation")
      end

      def permitted?
        return true unless login.first_run? && self.class.token_required?

        given = update(:token).to_s

        return true if given.present? &&
                       ActiveSupport::SecurityUtils.secure_compare(given, self.class.token)

        warn! "invalid-setup-token", field: "token"
        false
      end

      def password
        update(:password).to_s
      end
  end
end
