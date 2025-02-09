# frozen_string_literal: true
module Masks
  SRC = Pathname.new(__dir__).dirname
end

require "chronic_duration"
require "openid_connect"
require "device_detector"
require "fuzzyurl"
require "string-obfuscator"

require_relative "masks/version"
require_relative "masks/timing"
require_relative "masks/loader"
require_relative "masks/scopes"
require_relative "masks/settings"
require_relative "masks/errors"
require_relative "masks/seeder"
require_relative "masks/seedable"

require_relative "masks/mode"
require_relative "masks/client_mode"
require_relative "masks/session"
require_relative "masks/routing"

require_relative "masks/actor_settings"
require_relative "masks/client_settings"

Dir[File.join(__dir__, "masks/shims", "*.rb")].each { |file| require file }

require_relative "masks/endpoint"
require_relative "masks/endpoints/protected_endpoint"

Dir[File.join(__dir__, "masks/controllers", "*.rb")].each do |file|
  require file
end

require_relative "masks/railtie" if defined?(Rails::Railtie)

# Top-level module for masks.
module Masks
  class << self
    include ActiveSupport::Delegation

    # The full path to the masks conf dir.
    #
    # @return [String|nil]  The path, if available
    def conf_dir
      value = ENV["MASKS_DIR"]&.presence
      Pathname.new(value) if value
    rescue StandardError => e
      nil
    end

    # @return [String]
    def env
      ENV.fetch("MASKS_ENV", defined?(Rails) ? Rails.env.to_s : "production")
    end

    # @return [Logger]
    def logger
      @logger ||= Rails.logger
    end

    # Set the masks logger.
    #
    # @param  logger  [Logger]  A logger to use
    # @return [Logger] A logger
    def logger=(logger)
      @logger = logger
    end

    # The current masks mode.
    #
    # @return [Masks::Mode::Inquirer]
    def mode
      @mode ||= Mode::Inquirer.new(yml[:mode])
    end

    # Global masks configuration.
    #
    # @return  [Masks::ClientMode|Masks::ServerMode]
    def conf
      @conf ||= mode.build(yml.deep_stringify_keys)
    end

    # Shortcut to Masks::Timing helpers.
    #
    # Example:
    #
    # ```ruby
    # Masks.time.duration('10 minutes').from_now
    # ```
    #
    # @return [Masks::Timing]
    def time
      Masks::Timing.new
    end

    # @!method scopes
    #
    # @return [Masks::Scopes]
    delegate :scopes, to: :conf

    # @!method hello2()
    #
    # Outputs "hello world"
    delegate :actors,
             :clients,
             :provider,
             :providers,
             :seed,
             :url,
             :routing,
             :session,
             :devices,
             to: :conf,
             allow_nil: true

    # @!visibility private
    def reset!
      @conf = nil
      @yml = nil
    end

    # @!visibility private
    def yml
      @yml ||= Loader.yml("masks")
    end

    # @!visibility private
    def default_url_options
      return {} unless uri

      { protocol: uri.scheme, host: uri.hostname, port: uri.port }.compact
    end

    # @!visibility private
    def uri
      Addressable::URI.parse(url)
    end

    # @!visibility private
    def to_bool(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def rails_url(name, *args, **opts)
      Rails.application.routes.url_helpers.send(
        "#{name}_url",
        *args,
        **default_url_options.merge(opts),
      )
    end

    # @!visibility private
    def storage_url(variant)
      rails_url(:rails_storage_proxy, variant)
    end
  end
end
