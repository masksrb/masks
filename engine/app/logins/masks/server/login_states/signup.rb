module Masks
  module Server
    module LoginStates
      class Signup < LoginState
        EXPIRY = 12.hours
        WINDOW = 30.minutes
        HELD = "signup".freeze
        SIGNED_UP = "signed_up".freeze
        FIRST_RUN_STEPS = %w[identification credentials configuration].freeze
        STEPS = %w[identification credentials].freeze

        accepts :nickname, :email, :name, :phone, :password, :password_confirmation, :token, :passkey

        class << self
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

        handles "signup:passkey-challenge" do
          offer_passkey
        end

        handles "signup:passkey", limit: :verifying do
          claim_with_passkey
        end

        prompts "signup" do
          held.blank? || held["editing"]
        end

        prompts "signup-credentials" do
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
              "token" => login.first_run? && !held["vouched"],
              "minimum" => policy.password_minimum,
              "asks" => { "nickname" => policy.nickname, "email" => policy.email, "phone" => policy.phone },
              "fixed" => proven_email ? [ "email" ] : [],
              "credentials" => { "password" => policy.first_factor?(:password), "passkey" => policy.first_factor?(:passkey) },
              "nickname" => held.fetch("nickname") { suggested("nickname") },
              "email" => proven_email || held.fetch("email") { suggested("email") },
              "name" => held["name"],
              "phone" => held["phone"],
              "passkeyOptions" => @passkey_options
            }.compact
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

            return false unless policy.signup && policy.local?
            return false if identifier.blank? || located?(identifier)
            return false if policy.hidden && !login.state("inbox").proven?(identifier)

            !identifier.include?("@") || policy.admits?(identifier)
          end

          def proven_email
            return nil unless login.policy.hidden && login.state("inbox").proven?

            Inbox.address(login.identifier)
          end

          def located?(identifier)
            @located ||= {}
            @located.fetch(identifier) { @located[identifier] = Masks::Server::Actor.locate(identifier).present? }
          end

          def suggested(field)
            return nil if login.identifier.blank?

            (field == "email") == login.identifier.include?("@") ? login.identifier : nil
          end

          def hold
            return if held.present? && !held["editing"] && !identifying?
            return unless permitted?

            values = %w[nickname email name phone].to_h do |field|
              [ field, Masks::Server::Actor.normalize_value_for(field.to_sym, update(field)) ]
            end

            values["email"] = proven_email if proven_email

            return unless described?(values)

            login.store[HELD] = values.merge("vouched" => login.first_run?, "expires_at" => (Time.current + WINDOW).to_i)
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
            return warn!("factor-not-offered") unless login.policy.first_factor?(:password)

            refusal = Passwords.refusal(password, login.policy)

            credited = kept do
              warn! refusal, field: "password" if refusal
              warn! "mismatched-password", field: "password_confirmation" if password != update(:password_confirmation).to_s
            end

            return unless credited

            actor = create(password: password)

            return if actor.nil?

            settle(actor)
            login.noted! "pwd"
          end

          def offer_passkey
            return if held.blank? || held["editing"]
            return warn!("factor-not-offered") unless login.policy.first_factor?(:passkey)

            handle = held["webauthn_id"] || WebAuthn.generate_user_id
            options = relying_party.registration_options(
              Masks::Server::Actor.new(held.slice("nickname", "email", "name").merge("webauthn_id" => handle)),
              user_verification: "required", resident_key: "required"
            )

            @passkey_options = options.as_json
            login.store[HELD] = held.merge("webauthn_id" => handle, "passkey_challenge" => options.challenge)
          end

          def claim_with_passkey
            return if held.blank? || held["editing"]
            return warn!("factor-not-offered") unless login.policy.first_factor?(:passkey)

            challenge = held["passkey_challenge"]
            login.store[HELD] = held.except("passkey_challenge")

            return warn!("passkey-expired") if challenge.blank?

            credential = relying_party.verify_registration(JSON.parse(update(:passkey).to_s), challenge)

            unless credential.response.authenticator_data.user_verified?
              refused! "signup_passkey"
              return warn!("passkey-unverified")
            end

            actor = create(webauthn_id: held["webauthn_id"]) do |created|
              Masks::Server::Passkey.register!(actor: created, credential: credential)
            end

            return if actor.nil?

            settle(actor)
            factored! :second_factor, expiry: EXPIRY
            login.noted! "swk", "user", "mfa"
          rescue WebAuthn::Error, JSON::ParserError
            refused! "signup_passkey"
            warn! "passkey-unusable"
          end

          def settle(actor)
            Event.record!(Event::ACCOUNT_CREATED, actor: actor, first_run: @first_run,
                                                  signup: !@first_run, policy: login.policy.key)

            Verifications.open(actor: actor) unless !@first_run && login.policy.confirmation == SignInPolicy::CODE
            Confirmations.request_approval(actor) if actor.pending_approval_at.present?

            login.store.delete(HELD)
            login.identifier = actor.identifier
            login.actor = actor
            login.first_run!
            factored! :first_factor, expiry: EXPIRY
            login.store[SIGNED_UP] = { "first_run" => @first_run, "expires_at" => (Time.current + EXPIRY).to_i }
            login.store[Configure::HELD] = true if @first_run
            tenant.set_up! if @first_run
          end

          def create(password: nil, webauthn_id: nil)
            proven = proven_email

            Masks::Server::Actor.transaction do
              Masks::Server::Tenant.where(id: tenant.id).lock.pick(:id)

              @first_run = !Masks::Server::Actor.exists?
              login.first_run! unless @first_run

              unless @first_run || open_to?(held["email"] || held["nickname"])
                warn! "invalid-account"
                raise ActiveRecord::Rollback
              end

              now = Time.current
              actor = Masks::Server::Actor.new(
                nickname: held["nickname"],
                email: held["email"],
                name: held["name"],
                phone: held["phone"],
                password: password,
                webauthn_id: webauthn_id,
                activated_at: password ? nil : now,
                email_verified_at: proven.present? && held["email"] == proven ? now : nil,
                signed_up_at: now,
                pending_approval_at: !@first_run && login.policy.confirmation == SignInPolicy::APPROVAL ? now : nil,
                scopes: Scopes.join(@first_run ? Scopes::STANDARD + [ Scopes::MANAGE ] : login.policy.signup_scope_list)
              )

              unless actor.save
                warn! "invalid-account"
                raise ActiveRecord::Rollback
              end

              begin
                yield actor if block_given?
              rescue ActiveRecord::RecordInvalid
                warn! "passkey-unusable"
                raise ActiveRecord::Rollback
              end

              actor
            end
          end

          def relying_party
            RelyingParty.for(tenant, Current.origin)
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
            return true unless login.first_run?
            return true if held["vouched"]

            given = update(:token).to_s

            return true if given.present? &&
                           ActiveSupport::SecurityUtils.secure_compare(given, tenant.setup_token!)

            warn! "invalid-setup-token", field: "token"
            false
          end

          def password
            update(:password).to_s
          end
      end
    end
  end
end
