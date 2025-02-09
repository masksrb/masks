# frozen_string_literal: true

MASKS_SRC = Pathname.new(__dir__).dirname

require "chronic_duration"
require "phonelib"
require "webauthn"
require "fido_metadata"
require "validate_url"
require "valid_email"
require "validates_host"
require "graphql"
require "apollo_upload_server"
require "openid_connect"
require "device_detector"
require "fuzzyurl"
require "rotp"
require "string-obfuscator"

require_relative "masks/engine"
require_relative "masks/version"
require_relative "masks/timing"
require_relative "masks/scopes"
require_relative "masks/settings"
require_relative "masks/errors"
require_relative "masks/mode"
require_relative "masks/modes/client"
require_relative "masks/modes/server"
require_relative "masks/routing"
require_relative "masks/seeder"
require_relative "masks/session"

Dir[File.join(__dir__, "masks/shims", "*.rb")].each { |file| require file }

require_relative "masks/adapter"

Dir[File.join(__dir__, "masks/adapters", "*.rb")].each { |file| require file }

require_relative "cli/command"
require_relative "cli/runtime/model_command"
require_relative "cli/runtime/client_command"
require_relative "cli/runtime/conf_command"
require_relative "cli/runtime/actor_command"
require_relative "cli/runtime/provider_command"

require_relative "masks/prompt"

Dir[File.join(__dir__, "masks/prompts", "*.rb")].each { |file| require file }

require_relative "masks/endpoint"

Dir[File.join(__dir__, "masks/endpoints", "*.rb")].each { |file| require file }

Dir[File.join(__dir__, "masks/concerns", "*.rb")].each { |file| require file }

# Top-level module for masks.
module Masks
  class ModeInquirer
    def initialize(name)
      case name
      when "server"
        @class = "Masks::Modes::Server"
        @server = true
        @client = true
      when "client", nil
        @class = "Masks::Modes::Client"
        @client = true
      else
        raise InvalidModeError.new(yml[:mode])
      end

      @name = name
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

  class << self
    include ActiveSupport::Delegation

    def dir
      Pathname.new(
        (
          ENV["MASKS_DIR"]&.presence || Rails.root.join("config").to_s
        ).remove_suffix("/"),
      )
    rescue StandardError
      Masks::Engine.root.join("config")
    end

    # @return Logger
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
    # ---
    #
    # @return [Masks::ModeInquirer]
    def mode
      @mode ||= ModeInquirer.new(yml[:mode])
    end

    # Global masks configuration.
    #
    # ---
    #
    # @return  [Masks::Modes::Client|Masks::Modes::Server]
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

    # @!method actor(key, **opts)
    #
    # @param key [String] the key to use
    #
    # Outputs "hello world"
    delegate :actor, to: :conf

    # @!method scopes
    #
    # @return [Masks::Scopes]
    delegate :scopes, to: :conf

    # @!method hello2()
    #
    # Outputs "hello world"
    delegate :actor,
             :seed_actor,
             :client,
             :seed_client,
             :provider,
             :seed_provider,
             :seed,
             :url,
             :use_secrets,
             :use_sessions,
             :routing,
             to: :conf,
             allow_nil: true

    # @!visibility private
    def reset!
      @conf = nil
      @yml = nil
    end

    # @!visibility private
    def yml
      @yml ||= Shims::YML.layer("masks")
    end

    # @!visibility private
    def default_url_options
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

    # @!visibility private
    def storage_url(variant)
      Rails.application.routes.url_helpers.rails_storage_proxy_url(
        variant,
        **default_url_options,
      )
    end
  end
end
