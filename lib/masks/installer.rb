module Masks
  module Installer
    extend ActiveSupport::Concern

    def setting(*args, **opts)
      raise NotImplementedError
    end

    def modify(updates)
      raise NotImplementedError
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

      save! && Masks.logger.info("Saved '#{name}' installation...") if writable?

      filename = "app/assets/images/masks.png"

      self.light_logo_file = Masks::Engine.root.join(filename)
      self.dark_logo_file = Masks::Engine.root.join(filename)
      self.favicon_file = Masks::Engine.root.join(filename)

      ensure_actors
      ensure_clients
      ensure_providers

      seeder.instance_exec(&block) if block

      self
    rescue => e
      Masks.logger.error(e)
      Masks.logger.debug(e.backtrace.join("\n"))

      raise e
    ensure
      Masks.logger = logger
    end

    def duration(*keys, **args)
      Masks.time.duration(setting(*keys, **args))
    end

    def enabled?(key)
      setting(key, :enabled)
    end

    def light_logo_file=(path)
      nil
    end

    def dark_logo_file=(path)
      nil
    end

    def favicon_file=(path)
      nil
    end

    def favicon_url
      setting(:theme, :favicon_url)
    end

    def light_logo_url
      setting(:theme, :light_logo_url)
    end

    def dark_logo_url
      setting(:theme, :dark_logo_url)
    end

    def actor(*args, **opts)
      Masks::Actor.identify(*args, **opts)
    end

    def prompts
      setting(:prompts, default: []).map(&:constantize)
    end

    def provider(key, client: nil)
      provider ||= Masks::Provider.find_by(key:)
      provider if !client || client.provider?(provider)
    end

    def provider_types
      @provider_types ||=
        setting(:provider, :types, default: {})
          .map { |key, value| [key, value.constantize] }
          .to_h
    end

    %i[
      name
      url
      timezone
      region
      theme
      storage
      sessions
      devicejzz
      actors
    ].each do |key|
      define_method key do
        setting(key)
      end
    end

    def backup_codes
      {
        min_chars: setting("backup_codes", "min_chars", default: 8),
        max_chars: setting("backup_codes", "max_chars", default: 100),
        total: setting("backup_codes", "total", default: 10),
      }
    end

    def nicknames
      {
        min_chars: setting("nicknames", "min_chars", default: 4),
        max_chars: setting("nicknames", "max_chars", default: 20),
        format:
          setting("nicknames", "format", default: '\A[a-zA-Z][a-zA-Z0-9\-]+\z'),
      }
    end

    def emails
      setting(:emails, default: {}).merge(
        max_for_login: setting(:emails, :max_for_login, default: 5),
      )
    end

    def passwords
      {
        min_chars: setting("passwords", "min_chars", default: 8),
        max_chars: setting("passwords", "max_chars", default: 100),
        cooldown:
          setting("passwords", "change_cooldown", default: "15 minutes"),
      }
    end

    def default_client?
      setting(:client, :default)&.present?
    end

    def default_client
      @default_client ||=
        if value = setting(:client, :default)
          case value
          when Masks::Client
            value
          else
            client(value) if value&.present?
          end
        end
    end

    def client_defaults
      setting(:client, :defaults, default: {}).deep_stringify_keys
    end

    def client_types
      setting(:client, :types, default: {}).deep_stringify_keys
    end

    def client(key)
      Masks::Client.find_by(key:)
    end

    def public_settings
      (
        {
          name:,
          url:,
          needs_restart:,
          light_logo_url:,
          dark_logo_url:,
          favicon_url:,
          theme:,
          timezone:,
          region:,
          nicknames:,
          passwords:,
          backup_codes:,
          writable:,
        }
      )
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

    def management_client
      @management_client ||= client(management_client_key) if management?
    end

    def management_client_key
      setting(:manager, :client, default: "masks") if management?
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
      @scopes ||= Shims::YML.layer("scopes")

      Masks::Scopes.new(@scopes)
    end

    def phone_adapter
      @phone_adapter ||=
        begin
          case Masks.setting(:phones, :adapter)
          when "twilio"
            Masks::PhoneAdapters::TwilioPhone.new(self)
          when "test"
            Masks::PhoneAdapters::TestPhone.new(self)
          else
            Masks::PhoneAdapters::NilPhone.new(self)
          end
        end
    end

    private

    def ensure_actors
      Masks::Actor.seed_data.each { |key, yml| seeder.actor(key, **yml) }
    end

    def ensure_providers
      Masks::Provider.seed_data.each { |key, yml| seeder.provider(key, **yml) }
    end

    def ensure_clients
      Masks::Client.seed_data.each { |key, yml| seeder.client(key, **yml) }
    end
  end
end
