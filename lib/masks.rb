# frozen_string_literal: true

require "recursive-open-struct"
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
require_relative "masks/env"
require_relative "masks/errors"
require_relative "masks/installer"
require_relative "masks/routing"
require_relative "masks/seeder"
require_relative "masks/session"
require_relative "masks/shims/action_mailer"
require_relative "masks/shims/rails_secrets"
require_relative "masks/shims/fido"
require_relative "masks/shims/oauth_request"
require_relative "masks/shims/omniauth"
require_relative "masks/shims/yml"

# Top-level module for masks.
module Masks
  class << self
    include ActiveSupport::Delegation

    def logger
      @logger ||= Rails.logger
    end

    def logger=(l)
      @logger = l
    end

    def configure(&block)
      env.instance_exec(&block)
    end

    def default_url_options
      {
        protocol: Masks.uri.scheme,
        host: Masks.uri.hostname,
        port: Masks.uri.port,
      }.compact
    end

    def uri
      URI.parse(url)
    end

    def url
      env.url
    end

    def name
      env.name
    end

    def time
      Masks::Timing.new
    end

    def installation
      @install ||= env.installer.current
    rescue ActiveRecord::StatementInvalid
      nil
    end

    def parameter_filter
      @parameter_filter ||=
        ActiveSupport::ParameterFilter.new(
          Rails.application.config.filter_parameters,
        )
    end

    def asset(path, **args)
      File.open((args[:root] || Masks::Engine.root).join(path))
    end

    def to_bool(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    delegate :filter_param, to: :parameter_filter

    delegate :identify,
             :signup,
             :find,
             :actor,
             :client,
             :provider,
             :providers,
             :setting,
             :seed,
             to: :installation,
             allow_nil: true

    def env
      @env ||= Env.new(masks_yml)
    end

    def masks_yml
      @yml ||= Shims::YML.layer("masks")
    end

    def reset!
      @yml = nil
      @env = nil
      @install = nil
    end
  end
end
