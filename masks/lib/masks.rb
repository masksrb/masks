# frozen_string_literal: true

module Masks
  SRC = Pathname.new(__dir__).dirname
end

require 'ostruct'
require 'chronic_duration'
require 'device_detector'
require 'fuzzyurl'
require 'openid_connect'
require 'string-obfuscator'
require "vite_rails"
require "validate_url"
require "valid_email"
require "validates_host"

require_relative 'masks/timing'
require_relative 'masks/engine'
require_relative 'masks/version'
require_relative 'masks/loader'
require_relative 'masks/mode'
require_relative 'masks/errors'
require_relative 'masks/settings'
require_relative 'masks/modes/client_mode'
require_relative 'masks/modes/server_mode'
require_relative 'masks/modes/engine_mode'
require_relative 'masks/middleware/request'
require_relative 'masks/adapter'
require_relative 'masks/shims/rack'

# Settings
require_relative 'masks/settings/client'

# Seeds
require_relative 'masks/seedable'
require_relative 'masks/seeder'

# Sessions
require_relative 'masks/sessions/controller'
require_relative 'masks/sessions/device_data'
require_relative 'masks/sessions/throttle'
require_relative 'masks/sessions/server'

# Captcha
require_relative 'masks/captchas/recaptcha'
require_relative 'masks/captchas/turnstile'
require_relative 'masks/captchas/hcaptcha'

# Controller concern
require_relative 'masks/controller'

# Policies
require_relative 'masks/policy'
require_relative 'masks/policies/builder'
require_relative 'masks/policies/sub_policies'
require_relative 'masks/policies/request_matchers'
require_relative 'masks/policies/one_of'
require_relative 'masks/policies/request'
require_relative 'masks/policies/masks'
require_relative 'masks/policies/device'
require_relative 'masks/policies/client'
require_relative 'masks/policies/logged_in'
require_relative 'masks/policies/controller'
require_relative 'masks/policies/login'
require_relative 'masks/policies/sso'
require_relative 'masks/policies/oidc'
require_relative 'masks/policies/admin'
require_relative 'masks/policies/gql'


# Top-level module for masks.
module Masks
  class << self
    include ActiveSupport::Delegation

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

    # @return [String]
    def env
      ENV.fetch('MASKS_ENV', Rails.env&.to_s) || 'production'
    rescue StandardError
      'production'
    end

    def production?
      env == 'production'
    end

    # The full path to the masks conf dir.
    #
    # @return [String|nil]  The path, if available
    def conf_dir
      value = ENV['MASKS_DIR']&.presence
      Pathname.new(value) if value
    rescue StandardError
      nil
    end

    # The YML configuration.
    #
    # @return [Masks::Mode]
    def yml
      @yml ||= Masks::Loader.yml
    end

    # The current masks mode.
    #
    # @return [Masks::Mode]
    def mode
      @mode ||= begin
        mode = ENV['MASKS_MODE'] || yml.fetch(:mode)
        cls = "Masks::#{mode.classify}Mode".constantize
        cls.new(yml)
      end
    rescue => e
      raise InvalidModeError, e
    end

    delegate :logger, :logger=, to: :Rails
    delegate *%i[
      cls
      seed
      policy
      sessions
      devices
      actors
      clients
      providers
      adapter
    ], to: :mode

    def configure(&block)
      mode.instance_exec(&block)
    end

    # @!visibility private
    def reset!
      @mode = nil
      @yml = nil
      @config = nil

      masks_rb = Rails.root.join('config', 'masks.rb')

      Masks.configure do
        load masks_rb if File.exist?(masks_rb)
      end
    end
  end
end
