module Masks
  module Mode
    extend ActiveSupport::Concern

    included do
      include Masks::Settings

      setting :url,
              :string,
              env: "MASKS_URL",
              hardWardpublic: true,
              restarts: true
      setting :mode,
              :string,
              env: "MASKS_MODE",
              default: "client",
              restarts: true
      setting :name,
              :string,
              env: "MASKS_NAME",
              public: true,
              default: -> { default_name }
      setting :tz,
              :string,
              env: "MASKS_TZ",
              default: "Etc/UTC",
              public: true,
              restarts: true
      setting :debug,
              :string,
              env: "MASKS_DEBUG",
              public: true,
              default: -> { default_debug },
              restarts: true
      setting :conf_dir, :string, env: "MASKS_DIR", restarts: true
      setting :data_dir,
              :string,
              env: "MASKS_DATA_DIR",
              default: -> { Rails.root.join("data").to_s },
              restarts: true
      setting :client_key, :string, env: "MASKS_CLIENT_KEY", secret: true
      setting :private_key,
              :string,
              env: "MASKS_PRIVATE_KEY",
              default: -> { default_private_key },
              secret: true,
              restarts: true
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
      setting :device_class,
              :string,
              default: "Masks::Device",
              key: %i[device class]
      setting :device_cookie_name,
              :string,
              default: -> { "#{name.parameterize}-device" },
              key: %i[device cookie name]
      setting :device_cookie_lifetime,
              :string,
              default: "400 days",
              key: %i[device cookie lifetime]
      setting :device_inactive, :string, key: %i[device inactive]
      setting :client_id, :string, env: "MASKS_CLIENT_ID"
      setting :client_secret, :string, env: "MASKS_CLIENT_SECRET"
      setting :secret_key, :string, env: "MASKS_SECRET_KEY"
      setting :encryption_key, :string, env: "MASKS_ENCRYPTION_KEY"
      setting :deterministic_key, :string, env: "MASKS_DETERMINISTIC_KEY"
      setting :salt, :string, env: "MASKS_SALT"

      setting :login_endpoint, :string, default: "/login"
      setting :graphql_endpoint, :string, default: "/login.graphql"
      setting :sso_endpoint, :string, default: "/sso"
      setting :token_endpoint, :string, default: "/oidc/token"
      setting :userinfo_endpoint, :string, default: "/oidc/userinfo"
      setting :client_registration_endpoint, :string, default: "/oidc/client"
      setting :client_issuer_endpoint, :string, default: "/oidc/:client_id"
      setting :client_well_known_endpoint,
              :string,
              default: "/oidc/:client_id/.well-known"
      setting :client_jwks_endpoint, :string, default: "/oidc/:client_id/jwks"
      setting :manage_endpoint, :string, default: "/masks"
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

    def default_gql_endpoint
      url + "/login.graphql"
    end

    def use_secrets(config)
      config.secret_key_base = rails_secrets.secret_key
      config.active_record.encryption.primary_key =
        rails_secrets.encryption_key&.presence
      config.active_record.encryption.deterministic_key =
        rails_secrets.deterministic_key&.presence
      config.active_record.encryption.key_derivation_salt =
        rails_secrets.salt&.presence
    end

    def use_sessions(config)
      config.session_store :active_record_store, key: session_cookie_name
      config.to_prepare do
        config.session_options[
          :expire_after
        ] = Masks::SessionRecord.expire_after if Masks::SessionRecord.expire_after

        ActionDispatch::Session::ActiveRecordStore.session_class =
          Masks::SessionRecord

        ActiveRecord::SessionStore::Session.table_name = "masks_sessions"
      end
    end

    def rails_secrets
      @rails_secrets ||= Shims::RailsSecrets.new(self)
    end

    def endpoints
    end

    def db
      @db ||= Shims::RailsDatabase.new(self)
    end

    def modify(updates)
      merge_settings(updates)
    end

    def seeder
      @seeder ||= Masks::Seeder.new(self)
    end

    def seed(&block)
      logger = Masks.logger

      unless Rails.env.test?
        Masks.logger = ActiveSupport::Logger.new(STDOUT)
        Masks.logger.formatter = ->(severity, datetime, progname, msg) do
          "[masks] #{msg}\n"
        end
      end

      save! && Masks.logger.info("Saved '#{name}' installation...")

      seed_clients
      seed_actors
      seed_providers

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
      Masks::Actor.identify(*args, **opts)
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

    def scopes
      @scopes ||= Masks::Scopes.new(Shims::YML.layer("scopes"))
    end

    private

    def seed_actors
      Masks::Actor.seed_data.each { |key, yml| seeder.actor(key, **yml) }
    end

    def seed_providers
      Masks::Provider.seed_data.each { |key, yml| seeder.provider(key, **yml) }
    end

    def seed_clients
      Masks::Client.seed_data.each { |key, yml| seeder.client(key, **yml) }
    end
  end
end
