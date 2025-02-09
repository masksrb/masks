module Masks
  module Prompt
    extend ActiveSupport::Concern

    FACTOR1 = :first_factor
    FACTOR2 = :second_factor
    PROMPTS = %w[
      access-denied
      authorize
      backend-error
      device
      error
      expired-state
      first-factor
      identify
      invalid-redirect-uri
      login-code
      login-link-accept
      login-link
      missing-client
      missing-nonce
      missing-scopes
      profile
      reset-password
      second-factor
      sso-accept
      sso-error
      sso-link
      sso
      success
      unsupported-response-type
      verify-email
    ]

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
    SECOND_FACTORS = %w[webauthn one_time_password phone]
    FIRST_OR_SECOND = FIRST_FACTORS + SECOND_FACTORS
    BACKUP_CODES = ["backup_code"]
    FACTORS = FIRST_OR_SECOND + BACKUP_CODES

    included do
      include Masks::Settings

      cattr_accessor :prompt_map

      attr_reader :login
      attr_accessor :settings

      delegate :session,
               :extras,
               :path,
               :event,
               :event?,
               :prompt,
               :prompt=,
               :stages,
               :trusted?,
               :extras,
               :warn!,
               :updates,
               to: :login

      delegate :current_identifier,
               :current_device,
               :current_client,
               :current_actor,
               :current_oauth_request,
               to: :session
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

    def initialize(login, settings = {})
      raise unless login.is_a?(Masks::LoginEndpoint)

      @login = login
      @settings = settings
    end

    def request
      session.rails_request
    end

    def dispatch(name = nil, event: false)
      event ? handle(self.class.event(event)) : handle(self.class.on(name))
    end

    def sibling(name)
      case name
      when Class
        login.prompts.fetch(name.to_s)
      when String
        login
          .prompts
          .fetch(name) do
            login.prompts.fetch("Masks::Prompts::#{name.classify}")
          end
      when Symbol
        login.prompts.fetch("Masks::Prompts::#{name.to_s.classify}")
      else
        raise KeyError
      end
    end

    def show_settings?
      match?
    end

    private

    def handle(configs)
      Array(configs).each do |config|
        run_handler(config[:handler]) if config && handle?(config[:args] || {})
      end
    end

    def handle?(options)
      return true if options[:always]
      return false if login.prompt || login.settled?
      return false unless enabled?(options)

      match?
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

    def match?
      matchers = self.class.prompt_config[:matchers] || []
      matchers.any? { |v| run_handler(v, args: []) }
    end

    def verify_factor(*factors)
      raise if factors.empty?

      passed = false
      factors.each do |key|
        raise unless FACTORS.include?(key.to_s)

        result = sibling(key).verify

        next if result.nil?

        passed = result

        break
      end

      warn! "invalid-factor" unless passed

      passed
    end

    def on_first_factor?
      !current_identifier || !session[FACTOR1]
    end

    def on_profile?
      trusted? && sibling(:profile).visit?
    end

    def on_2fa?
      session[FACTOR1] &&
        (
          current_client&.second_factor? || current_actor&.second_factor? ||
            current_actor.review_second_factor?
        )
    end

    def change_2fa?
      changeable_2fa? &&
        (!current_actor.second_factor? || verify_factor(*FIRST_OR_SECOND))
    end

    def changeable_2fa?
      on_2fa? || on_profile?
    end
  end
end
