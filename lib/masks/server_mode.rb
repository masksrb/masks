module Masks
  class ServerMode
    include Masks::Mode

    SUBJECT_TYPES = %w[public-uuid public-identifier pairwise-uuid]

    setting :port, :int, env_only: "MASKS_PORT", default: 5000
    setting :workers, :int, env_only: "MASKS_WORKERS", default: 0
    setting :run_workers, :boolean, env_only: "MASKS_RUN_WORKERS", default: true
    setting :skip_migrations,
            :boolean,
            env_only: "MASKS_SKIP_MIGRATIONS",
            default: false
    setting :threads, :int, env_only: "MASKS_THREADS", default: 3
    setting :local, :boolean, default: false

    setting :internal_client, :string
    setting :management_client, :string, default: "masks"
    setting :client_defaults, :json
    setting :client_types, :json
    setting :redirect_missing_clients, :string, default: -> { theme_homepage }

    setting :provider_types,
            :json,
            default: -> { default_providers },
            key: %i[providers types]

    setting :phone_adapter,
            :string,
            env: "MASKS_PHONE_ADAPTER",
            default: "twilio",
            key: %i[phone adapter]
    setting :phone_country,
            :string,
            env: "MASKS_PHONE_COUNTRY",
            default: "CA",
            public: true

    setting :storage_adapter,
            :string,
            env: "MASKS_STORAGE_ADAPTER",
            default: "disk",
            key: %i[storage adapter]
    setting :email_adapter,
            :string,
            env: "MASKS_EMAIL_ADAPTER",
            key: %i[email adapter]
    setting :email_limit, :int, default: 5, key: %i[email limit]
    setting :email_from, :string, env: "MASKS_EMAIL_FROM", key: %i[email from]
    setting :email_reply_to,
            :string,
            env: "MASKS_EMAIL_REPLY_TO",
            key: %i[email reply_to]

    setting :actor_scopes, :json, default: -> { ["openid"] }
    setting :actor_inactive, :string, key: %i[actor inactive]
    setting :subject_types, [:string], default: SUBJECT_TYPES
    setting :backup_code_min_chars,
            :int,
            default: 8,
            public: true,
            key: %i[backup_code min_chars]
    setting :backup_code_max_chars,
            :int,
            default: 100,
            public: true,
            key: %i[backup_code max_chars]
    setting :backup_code_limit,
            :int,
            default: 10,
            public: true,
            key: %i[backup_code limit]
    setting :nickname_format,
            :string,
            default: '\A[a-zA-Z][a-zA-Z0-9\-]+\z',
            public: true,
            key: %i[nickname format]
    setting :nickname_min_chars,
            :int,
            default: 4,
            public: true,
            key: %i[nickname min_chars]
    setting :nickname_max_chars,
            :int,
            default: 20,
            public: true,
            key: %i[nickname max_chars]
    setting :password_min_chars,
            :int,
            default: 8,
            public: true,
            key: %i[password min_chars]
    setting :password_max_chars,
            :int,
            default: 100,
            public: true,
            key: %i[password max_chars]
    setting :password_change_cooldown,
            :string,
            default: "15 minutes",
            public: true,
            key: %i[password change_cooldown]
    setting :otp_issuer, :string, default: -> { name }, key: %i[otp issuer]
    setting :webauthn_name,
            :string,
            default: -> { name },
            key: %i[webauthn name]
    setting :webauthn_origins,
            :string,
            default: -> { [Masks.url] },
            key: %i[webauthn origins]
    setting :webauthn_algos,
            [:string],
            default: %w[
              ES256
              ES384
              ES512
              PS256
              PS384
              PS512
              RS256
              RS384
              RS512
              RS1
            ]

    setting :theme_homepage,
            :string,
            public: true,
            key: %i[theme homepage],
            default: -> { url }
    setting :theme_name,
            :string,
            default: -> { name },
            public: true,
            key: %i[theme name]
    setting :theme_layout,
            :string,
            default: "masks/application",
            key: %i[theme layout]
    setting :theme_view, :string, default: "masks/login", key: %i[theme view]
    setting :light_logo_url, :string, public: true, key: %i[theme light_logo]
    setting :dark_logo_url, :string, public: true, key: %i[theme dark_logo]
    setting :favicon_url, :string, public: true, key: %i[theme favicon]
    setting :styles_url, :string, public: true, key: %i[theme styles]
    setting :terms_url, :string, public: true, key: %i[theme terms]

    setting :db_url, :string, env: "MASKS_DB_URL", key: %i[db url]
    setting :db_name, :string, env: "MASKS_DB_NAME", key: %i[db name]
    setting :db_adapter,
            :string,
            env: "MASKS_DB_ADAPTER",
            key: %i[db adapter],
            default: "sqlite3"
    setting :queue_db_url,
            :string,
            env: "MASKS_QUEUE_DB_URL",
            key: %i[db queue url]
    setting :queue_db_name,
            :string,
            env: "MASKS_QUEUE_DB_NAME",
            key: %i[db queue name]
    setting :queue_db_adapter,
            :string,
            env: "MASKS_QUEUE_DB_ADAPTER",
            key: %i[db queue adapter]
    setting :cache_db_url,
            :string,
            env: "MASKS_CACHE_DB_URL",
            key: %i[db cache url]
    setting :cache_db_name,
            :string,
            env: "MASKS_CACHE_DB_NAME",
            key: %i[db cache name]
    setting :cache_db_adapter,
            :string,
            env: "MASKS_CACHE_DB_ADAPTER",
            key: %i[db cache adapter]
    setting :websockets_db_url,
            :string,
            env: "MASKS_WEBSOCKETS_DB_URL",
            key: %i[db websockets url]
    setting :websockets_db_name,
            :string,
            env: "MASKS_WEBSOCKETS_DB_NAME",
            key: %i[db websockets name]
    setting :websockets_db_adapter,
            :string,
            env: "MASKS_WEBSOCKETS_DB_ADAPTER",
            key: %i[db websockets adapter]
    setting :sessions_db_url,
            :string,
            env: "MASKS_SESSIONS_DB_URL",
            key: %i[db sessions url]
    setting :sessions_db_name,
            :string,
            env: "MASKS_SESSIONS_DB_NAME",
            key: %i[db sessions name]
    setting :sessions_db_adapter,
            :string,
            env: "MASKS_SESSIONS_DB_ADAPTER",
            key: %i[db sessions adapter]

    setting :sentry_dsn, :string, env: "MASKS_SENTRY_DSN", key: %i[sentry dsn]
    setting :newrelic_app,
            :string,
            env: "MASKS_NEWRELIC_APP",
            key: %i[newrelic app],
            default: -> { name }
    setting :newrelic_license_key,
            :string,
            env: "MASKS_NEWRELIC_LICENSE_KEY",
            key: %i[newrelic license_key],
            secret: true

    setting :actor_model, :string, default: "Masks::Actor"
    setting :client_model, :string, default: "Masks::Client"
    setting :device_model, :string, default: "Masks::Device"
    setting :token_model, :string, default: "Masks::Token"

    setting :use_secrets, :boolean, default: true
    setting :use_sessions, :boolean, default: true

    timestamps

    def initialize(settings)
      @settings = settings
    end

    def cli_commands
      [
        Masks::Server::ConfCommand.new,
        Masks::Server::ActorCommand.new,
        Masks::Server::ClientCommand.new,
        Masks::Server::ProviderCommand.new,
      ]
    end

    def settings
      if install
        install.settings
      else
        @settings ||= {}
      end
    end

    def settings=(v)
      if install
        install.settings = v
      else
        @settings = v
      end
    end

    def default_providers
      {
        oidc: "Masks::Providers::GenericOpenid",
        oauth: "Masks::Providers::GenericOauth",
        github: "Masks::Providers::Github",
        google: "Masks::Providers::Google",
        facebook: "Masks::Providers::Facebook",
        twitter: "Masks::Providers::Twitter",
        apple: "Masks::Providers::Apple",
      }
    end

    def adapter_types
      @adapter_types ||=
        Dir
          .glob(Masks::Engine.root.join("lib/masks/adapters/**/*_adapter.rb"))
          .map do |file|
            key = File.basename(file, "_adapter.rb")
            cls = "Masks::Adapters::#{key.classify}Adapter".constantize
            cls.new(key, {})
          end
    end

    def default_prompts
      %w[
        Masks::Prompts::Device
        Masks::Prompts::Signup
        Masks::Prompts::SingleSignOn
        Masks::Prompts::Identifier
        Masks::Prompts::LoginLink
        Masks::Prompts::Password
        Masks::Prompts::FirstFactor
        Masks::Prompts::Phone
        Masks::Prompts::Webauthn
        Masks::Prompts::OneTimePassword
        Masks::Prompts::BackupCode
        Masks::Prompts::SecondFactor
        Masks::Prompts::Email
        Masks::Prompts::ResetPassword
        Masks::Prompts::Oauth
        Masks::Prompts::Profile
        Masks::Prompts::LastLogin
        Masks::Prompts::Internal
      ]
    end

    def local
      @settings["local"]
    end

    def local=(v)
      @settings["local"] = v
    end

    def prompts
      default_prompts.map(&:constantize)
    end

    def provider_map
      (provider_types || {})
        .map { |key, value| [key.to_s, value.constantize] }
        .to_h
    end

    def install
      @install ||=
        unless local
          Masks::Installation.active.first ||
            Masks::Installation.new(settings: @settings)
        end
    rescue ActiveRecord::RecordNotFound,
           ActiveRecord::StatementInvalid,
           NameError
      nil
    end

    delegate :created_at, :updated_at, to: :install

    def writable?
      !!install
    end

    def new_record?
      !install
    end

    def save!
      install&.save!
    end

    def favicon_url
      return Masks.storage_url(install.favicon) if install&.favicon&.attached?

      super
    end

    def light_logo_url
      if install&.light_logo&.attached?
        return Masks.storage_url(install.light_logo)
      end

      super
    end

    def dark_logo_url
      if install&.dark_logo&.attached?
        return Masks.storage_url(install.dark_logo)
      end

      super
    end

    def styles_url
      return Masks.storage_url(install.styles) if install&.dark_logo&.attached?

      super
    end

    delegate :favicon, :light_logo, :dark_logo, :styles, to: :install

    def favicon_file=(file)
      install.upload_file(:favicon, file)
    end

    def light_logo_file=(file)
      install.upload_file(:light_logo, file)
    end

    def dark_logo_file=(file)
      install.upload_file(:dark_logo, file)
    end

    def styles_file=(file)
      install.upload_file(:styles, file)
    end

    def adapters
      @adapters ||=
        begin
          adapters =
            (self.settings["adapters"] || {}).deep_merge(
              install.settings["adapters"] || {},
            )
          adapters
            .map do |k, v|
              next if v["deleted"]

              [k.to_s, Masks::Adapter.build(k, v)]
            rescue => e
              nil
            end
            .compact
            .to_h
        end
    end

    def modify_adapter(**args)
      key = args.delete(:key)

      install.settings["adapters"] ||= {}
      install.settings["adapters"][key] ||= {}

      if args[:deleted]
        install.settings["adapters"][key].clear
        install.settings["adapters"][key].merge!("deleted" => true)
      else
        install.settings["adapters"][key].merge!(
          args.deep_stringify_keys.merge("deleted" => false),
        )
      end

      @adapters = nil

      self
    end

    def client_defaults=(v)
      settings["client_defaults"] ||= {}
      settings["client_defaults"].deep_merge!(v.deep_stringify_keys)
    end
  end
end
