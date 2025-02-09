module Masks
  module Mode
    class Inquirer
      def initialize(name)
        case name
        when "server"
          @class = "Masks::ServerMode"
          @server = true
          @client = true
          @name = "server"
        when "client", nil
          @class = "Masks::ClientMode"
          @client = true
          @name = "client"
        else
          raise Errors::InvalidMode.new(yml[:mode])
        end
      end

      def to_s
        @name
      end

      def build(yml)
        @class.constantize.new(yml.deep_stringify_keys)
      end

      def client?
        !!@client
      end

      def server?
        !!@server
      end
    end

    extend ActiveSupport::Concern

    included do
      include Masks::Settings

      setting :url, :string, env: "MASKS_URL"
      setting :mode, :string, env: "MASKS_MODE", default: "client"
      setting :name,
              :string,
              env: "MASKS_NAME",
              public: true,
              default: -> { default_name }
      setting :tz, :string, env: "MASKS_TZ", default: "Etc/UTC", public: true
      setting :debug,
              :string,
              env: "MASKS_DEBUG",
              public: true,
              default: -> { default_debug }
      setting :conf_dir, :string, env: "MASKS_DIR"
      setting :data_dir,
              :string,
              env: "MASKS_DATA_DIR",
              default: -> { Rails.root.join("data").to_s }
      setting :private_key,
              :string,
              env: "MASKS_PRIVATE_KEY",
              default: -> { default_private_key },
              secret: true
      setting :secret_key, :string, env: "MASKS_SECRET_KEY", secret: true
      setting :encryption_key,
              :string,
              env: "MASKS_ENCRYPTION_KEY",
              secret: true
      setting :deterministic_key,
              :string,
              env: "MASKS_DETERMINISTIC_KEY",
              secret: true
      setting :salt, :string, env: "MASKS_SALT", secret: true
      setting :session_cookie_name,
              :string,
              default: -> { "#{name.parameterize}-session" },
              key: %i[session cookie name]
      setting :session_cookie_lifetime,
              :string,
              key: %i[session cookie lifetime]
      setting :session_inactive,
              :string,
              default: "120 days",
              key: %i[session inactive]
      setting :device_cookie_name,
              :string,
              default: -> { "#{name.parameterize}-device" },
              key: %i[device cookie name]
      setting :device_cookie_lifetime,
              :string,
              default: "400 days",
              key: %i[device cookie lifetime]
      setting :session_model, :string, default: "Masks::Session"
      setting :device_inactive, :string, key: %i[device inactive]

      setting :login_endpoint, :string, default: "/login"
      setting :graphql_endpoint, :string, default: "/login.graphql"
      setting :sso_endpoint, :string, default: "/sso/:provider_id"
      setting :client_issuer_endpoint, :string, default: "/login/:client_id"
      setting :client_registration_endpoint, :string, default: "/oidc/client"
      setting :userinfo_endpoint, :string, default: "/oidc/userinfo"
      setting :token_endpoint, :string, default: "/oidc/token"
      setting :manage_endpoint, :string, default: "/masks"
      setting :callback_endpoint, :string, default: "/callback"
      setting :oidc_endpoints, :boolean, default: true
    end

    def endpoint(name)
      path = setting("#{name}_endpoint")
      uri + endpoint.delete_prefix("/") if path
    end

    def default_name
      Rails.application.name.humanize
    rescue StandardError
      "masks"
    end

    def default_debug
      Rails.env.development?
    rescue StandardError
      false
    end

    def default_private_key
      "#{data_dir.chomp("/")}/masks.key" if data_dir
    end

    def rails_secrets
      @rails_secrets ||= Shims::RailsSecrets.new(self)
    end

    def db
      @db ||= Shims::RailsDatabase.new(self)
    end

    def modify(updates)
      merge_settings(updates)
    end

    def seed(&block)
      logger = Masks.logger

      unless Rails.env.test?
        Masks.logger = ActiveSupport::Logger.new(STDOUT)
        Masks.logger.formatter = ->(severity, datetime, progname, msg) do
          "[masks] #{msg}\n"
        end
      end

      save! && Masks.logger.info("Seeding masks installation: '#{name}'")

      seeder.actor(actors.seed_data.values)
      seeder.client(clients.seed_data.values)
      seeder.provider(providers.seed_data.values)
      seeder.instance_exec(&block) if block

      self
    rescue => e
      Masks.logger.error(e)
      Masks.logger.debug(e.backtrace.join("\n"))

      raise e
    ensure
      Masks.logger = logger
    end

    def duration(key, **args)
      Masks.time.duration(setting(key), **args)
    end

    def actor(*args, **opts)
      actors.identify(*args, **opts)
    end

    def provider(key, client: nil)
      provider ||= Masks::Provider.find_by(key:)
      provider if !client || client.provider?(provider)
    end

    def client(key, **attrs)
      client = Masks::Client.find_by(key:)
      if attrs.key?(:internal) &&
           (!client || client.internal? != attrs[:internal])
        return
      end
      client
    end

    def public_json
      public_settings
    end

    def public_settings
      self
        .class
        .settings
        .map do |k, conf|
          next unless conf[:public]

          [k, send(k)]
        end
        .compact
        .to_h
    end

    def writable
      false
    end

    def writable?
      writable
    end

    def management?
      setting(:management)
    end

    def manager
      @manager ||=
        find(
          setting(:manager, :nickname) || setting(:manager, :email),
        ) if management?
    end

    def find(identifier)
      actor = identify(identifier)
      actor if actor.persisted?
    end

    def identify(identifier)
      if identifier&.include?("@")
        Actor.from_login_email(identifier)
      else
        Actor.find_or_initialize_by(nickname: identifier)
      end
    end

    def needs_restart
      false
    end

    def clients
      client_model.constantize
    end

    def actors
      actor_model.constantize
    end

    def providers
      Masks::Provider # For now...
    end

    def devices
      device_model.constantize
    end

    def session(*args, **opts, &block)
      session_model.constantize.new(*args, **opts, &block)
    end

    private

    def seeder
      @seeder ||= Masks::Seeder.new(self)
    end

    # def seed_actors
    #   actors.seed_data.each { |key, yml| seeder.actor(key, **yml) }
    # end

    # def seed_providers
    #   Masks::Provider.seed_data.each { |key, yml| seeder.provider(key, **yml) }
    # end

    # def seed_clients
    #   clients.seed_data.each { |key, yml| seeder.client(key, **yml) }
    # end
  end
end
