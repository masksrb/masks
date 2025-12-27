# frozen_string_literal: true

module Masks
  module Mode
    extend ActiveSupport::Concern

    DEFAULT_CLASSES = {
      device_detector: 'DeviceDetector',
      request_policy: 'Masks::RequestPolicy',
      controller_policy: 'Masks::ControllerPolicy'
    }

    SUBJECT_TYPES = %w[public-uuid public-identifier pairwise-uuid]
    CLIENT_TYPES = {
      internal: {
        internal: true,
        redirect_uris: ["/", "/*"],
        fuzzy_redirect_uri: true,
      }
    }

    included do
      include Masks::Settings

      setting :id, :string, key: :mode
      setting :url, :string, env: 'MASKS_URL'
      setting :name,
              :string,
              env: 'MASKS_NAME',
              default: -> { default_name }
      setting :tz, :string, env: 'MASKS_TZ', default: 'Etc/UTC', public: true
      setting :debug,
              :string,
              env: 'MASKS_DEBUG',
              public: true,
              default: -> { default_debug }
      setting :data_dir,
              :string,
              env: 'MASKS_DATA_DIR',
              default: -> { Rails.root.join('data').to_s }
      setting :adapters, :json, default: -> { {} }
      setting :light_logo_url, :string, public: true
      setting :dark_logo_url, :string, public: true
      setting :favicon_url, :string, public: true
      setting :styles_url, :string, public: true
      setting :terms_url, :string, public: true
      setting :homepage, :string, public: true
      setting :login_layout, :string, default: 'masks/client', key: %i[theme layouts login]
      setting :client_layout, :string, default: 'masks/client', key: %i[theme layouts client]
      setting :device_cookie, :string, default: '_device'
      setting :device_cookie_lifetime, :string, default: '400 days'
      setting :policies, :json, default: -> { {} }
      setting :classes, :json, default: -> { DEFAULT_CLASSES }
      setting :client_types, :json, default: CLIENT_TYPES
      setting :subject_types, [:string], default: SUBJECT_TYPES
      setting :default_client, :string, default: :default
    end

    attr_accessor :settings

    def initialize(yml = {})
      @settings = yml.stringify_keys
    end

    def has_logo?
      light_logo_url && dark_logo_url
    end

    def clients
      cls :client
    end

    def actors
      cls :actor
    end

    def providers
      cls :provider
    end

    def class_name(name)
      self.classes.fetch(name, "Masks::#{name.to_s.classify}")
    end

    def cls(name)
      class_name(name).constantize
    end

    def adapter(name)
      cls("#{name}_adapter").new(name.to_sym, Masks.mode.adapters.fetch(name.to_sym, nil))
    end

    def policy(type = :request, **opts, &block)
      @policies ||= {}
      @policies[type.to_s] ||= begin
        defaults = self.policies[type.to_s]
        policies = nil
        case defaults
        when Array
          policies = defaults
          defaults = {}
        when Hash
          policies = defaults.delete(:policies)
          defaults = defaults.deep_symbolize_keys
        end

        config = (defaults || {}).merge(opts.merge(type:))
        policy = cls("#{config[:as] || type}_policy").new(**config)
        policies&.each do |p|
          policy.add(p[:type], **p)
        end

        policy
      end
      @policies[type.to_s].run(&block) if block_given?
      @policies[type.to_s]
    end

    def seed(&block)
      logger = Masks.logger

      unless Rails.env.test?
        Masks.logger = ActiveSupport::Logger.new(STDOUT)
        Masks.logger.formatter = ->(severity, datetime, progname, msg) do
          "[masks] #{msg}\n"
        end
      end

      Masks.logger.info("Seeding masks installation: '#{name}'")

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

    private

    def seeder
      @seeder ||= Masks::Seeder.new
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
  end
end
