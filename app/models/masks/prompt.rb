module Masks
  module Prompt
    extend ActiveSupport::Concern

    SETUP = "setup"
    CLEANUP = "cleanup"
    OAUTH = "oauth"
    AUTH = "auth"
    PREAUTH = "preauth"
    POSTAUTH = "postauth"
    LOGIN = "login"
    FAILED = "failed"
    SETTLED = "settled"
    RESET = "reset"
    LOGOUT = "logout"
    SSO = "sso"
    EVENTS = [
      SETUP,
      OAUTH,
      AUTH,
      PREAUTH,
      POSTAUTH,
      LOGIN,
      SETTLED,
      FAILED,
      SSO,
      RESET,
      LOGOUT,
    ]

    FIRST_FACTORS = %w[email password]
    SECOND_FACTORS = %w[webauthn otp phone]
    FIRST_OR_SECOND = FIRST_FACTORS + SECOND_FACTORS
    BACKUP_CODES = ["backup_codes"]
    FACTORS = FIRST_OR_SECOND + BACKUP_CODES

    included do
      cattr_accessor :prompt_map

      attr_reader :entry

      delegate :session,
               :extras,
               :path,
               :params,
               :event,
               :event?,
               :prompt,
               :prompt=,
               :stages,
               :trusted?,
               :extras,
               :warn!,
               :updates,
               to: :entry
    end

    class_methods do
      def match(method = nil, &block)
        prompt_config[:matchers] ||= []
        prompt_config[:matchers] << (method || block)
      end

      def event(key, method = nil, **args, &block)
        key = "@#{key}"
        handlers(key => { handler: method || block, args: }) if method || block
        prompt_config.dig(:handlers, key)
      end

      def on(key, method = nil, **args, &block)
        handlers(key => { handler: method || block, args: }) if method || block
        prompt_config.dig(:handlers, key.to_s)
      end

      def setup(*args, **opts, &block)
        on(SETUP, *args, **opts.merge(always: true), &block)
      end

      def login(*args, **opts, &block)
        on(LOGIN, *args, **opts.merge(always: true), &block)
      end

      def cleanup(*args, **opts, &block)
        on(CLEANUP, *args, **opts.merge(always: true), &block)
      end

      def prompt(key, **args, &block)
        on(AUTH, **args) do
          result = instance_exec(&block)
          self.prompt ||= key if result && !prompt
        end
      end

      def method_missing(name, *args, **opts, &block)
        if EVENTS.include?(name.to_s)
          on(name.to_s, *args, **opts, &block)
        else
          super
        end
      end

      def prompt_config
        self.prompt_map ||= {}
        self.prompt_map[name] ||= {}
      end

      def handlers(**handlers)
        prompt_config[:handlers] ||= {}

        handlers.each do |k, v|
          prompt_config[:handlers] ||= {}
          prompt_config[:handlers][k] ||= []

          (v.is_a?(Array) ? v : [v]).each do |handler|
            prompt_config[:handlers][k] << handler
          end
        end

        prompt_config[:handlers]
      end
    end

    def initialize(entry)
      @entry = entry
    end

    def request
      session.rails_request
    end

    def identifier
      session.current_identifier
    end

    def client
      session.current_client
    end

    def device
      session.current_device
    end

    def actor
      session.current_actor
    end

    def second_factor
      session.current_second_factor
    end

    def oauth_request
      session.current_oauth_request
    end

    def dispatch(name = nil, event: false)
      event ? handle(self.class.event(event)) : handle(self.class.on(name))
    end

    def sibling(name)
      case name
      when Class
        entry.prompts.fetch(name.to_s)
      when String
        entry
          .prompts
          .fetch(name) { prompts.fetch("Masks::Prompts::#{name.classify}") }
      when Symbol
        entry.prompts.fetch("Masks::Prompts::#{name.to_s.classify}")
      else
        raise KeyError
      end
    end

    private

    def handle(configs)
      Array(configs).each do |config|
        run_handler(config[:handler]) if config && handle?(config[:args] || {})
      end
    end

    def handle?(options)
      return true if options[:always]
      return false if entry.prompt || entry.settled?
      return false unless enabled?(options)

      matchers = self.class.prompt_config[:matchers] || []
      result = matchers.any? { |v| run_handler(v, args: [options]) }
    end

    def run_handler(handler, args: [])
      case handler
      when Symbol
        send(handler)
      when Proc
        instance_exec(*args, &handler)
      end
    end

    def enabled?(args)
      return false if args[:trusted] && !trusted?
      return false if args[:factors] && !verify_factor(*args[:factors])
      return false if args[:if] && !run_handler(args[:if])
      return false if args[:unless] && run_handler(args[:unless])

      true
    end

    def on_first_factor?
      !identifier || !session[Entry::FACTOR1]
    end

    def on_profile?
      trusted? && sibling(:profile).visit?
    end

    def on_2fa?
      session[Entry::FACTOR1] &&
        (
          client&.second_factor? || actor&.second_factor? ||
            actor.review_second_factor?
        )
    end

    def change_2fa?
      changeable_2fa? &&
        (!actor.second_factor? || verify_factor(*FIRST_OR_SECOND))
    end

    def changeable_2fa?
      on_2fa? || on_profile?
    end

    def verify_factor(*allowed)
      raise if allowed.empty?

      passed = false

      allowed.each do |key|
        raise unless FACTORS.include?(key.to_s)

        result = send("verify_#{key}")

        next if result.nil?

        passed = result

        break
      end

      warn! "invalid-factor" unless passed

      passed
    end

    def verify_email
      return unless client.allow_emails? && updates["email"]

      code = updates.dig("email", "code")
      link =
        actor.login_links.active.for_verification.find_by(
          code:,
          email: verified_email,
        )

      if link
        link.verified!

        true
      else
        warn! "invalid-code", code
      end
    end

    def verify_webauthn
      return unless client.allow_webauthn? && updates["webauthn"]

      webauthn = WebAuthn::Credential.from_get(updates["webauthn"])
      credential = actor&.hardware_keys&.find_by(external_id: webauthn.id)
      challenge = session[:webauthn_challenge]

      return warn! "invalid-webauthn" unless credential && challenge

      begin
        webauthn.verify(
          challenge,
          public_key: credential.public_key,
          sign_count: credential.sign_count,
        )

        credential.update!(
          sign_count: webauthn.sign_count,
          verified_at: Time.now.utc,
        )

        session[Entry::FACTOR2] = client.expires_at(:second_factor_webauthn)
      rescue => e
        warn! "webauthn-error"
      end
    end

    def verify_phone
      return unless client.allow_phones? && updates["phone"]

      verify_phone_with_code(verified_phone, updates.dig("phone", "code"))
    end

    def verify_phone_with_code(phone, code)
      if phone.verify_code(code)
        session[Entry::FACTOR2] = client.expires_at(:second_factor_phone)
      else
        warn! "invalid-code", code
      end
    end

    def verify_otp
      return unless client.allow_otp? && updates["otp"]

      otp_secret = verified_otp_secret
      otp_code = updates.dig("otp", "code")

      if otp_secret&.verify_otp(otp_code)
        session[Entry::FACTOR2] = client.expires_at(:second_factor_otp)
      else
        warn! "invalid-code", otp_code
      end
    end

    def verify_otp_with_code(otp_secret, code)
      if otp_secret&.verify_otp(code)
        session[Entry::FACTOR2] = client.expires_at(:second_factor_otp)
      else
        warn! "invalid-code", code
      end
    end

    def verify_backup_code
      return unless client.allow_backup_codes? && updates["backupCode"]

      if actor&.verify_backup_code(updates["backupCode"])
        session[Entry::FACTOR2] = client.expires_at(:second_factor_backup_code)
      else
        warn! "invalid-code", updates["backupCode"]
      end
    end

    def verify_password
      return unless client.allow_passwords? && updates["password"]

      if actor&.authenticate(updates["password"])
        session[Entry::FACTOR1] = client.expires_at(:first_factor_password)
      else
        warn! "invalid-credentials"
        false
      end
    end

    def verified_phone
      @verified_phone ||=
        actor&.phones.find_by(number: updates.dig("phone", "number"))
    end

    def verified_email
      @verified_email ||=
        actor.emails.for_login.find_by(
          address: updates.dig("email", "address"),
        ) if updates["email"]
    end

    def verified_otp_secret
      @verified_otp_secret ||=
        actor.otp_secrets.find_by(
          public_id: updates.dig("otp", "id"),
        ) if updates["otp"]
    end
  end
end
