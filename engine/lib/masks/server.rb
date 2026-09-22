require "bcrypt"
require "jwt"
require "ruby-saml"
require "rack/oauth2"
require "openid_connect"
require "rqrcode"
require "rotp"
require "webauthn"
require "fido_metadata"
require "device_detector"
require "graphql"
require "premailer/rails"
require "vite_rails"

module Masks
  PROTOCOL_VERSION = 1

  def self.to_bool(val, default: false)
    return default if val.nil?

    ActiveModel::Type::Boolean.new.cast(val)
  end

  module Server
    class << self
      def table_name_prefix
        ""
      end

      def config
        ::Rails.application.config.masks
      end

      def engine?
        config.mode == :engine
      end

      def secret_key_base
        return ::Rails.application.secret_key_base unless engine?

        config.secret.presence ||
          ::Rails.application.key_generator.generate_key("masks/server secret_key_base", 64).unpack1("H*")
      end

      def key_generator
        return ::Rails.application.key_generator unless engine?

        @key_generator ||= ActiveSupport::CachingKeyGenerator.new(
          ActiveSupport::KeyGenerator.new(secret_key_base, iterations: 1000)
        )
      end

      def message_verifier(purpose)
        return ::Rails.application.message_verifier(purpose) unless engine?

        ActiveSupport::MessageVerifier.new(key_generator.generate_key("masks/server #{purpose}"))
      end

      def actor_for(request)
        tenant = Tenant.resolve(request.host)
        return nil if tenant.nil?

        secret = cookies_for(request).encrypted[:masks_session]
        return nil if secret.blank?

        Tenant.switch(tenant) { Session.resume(secret)&.actor }
      end

      def cookies_for(request)
        env = request.env.except("action_dispatch.cookies").merge(
          "action_dispatch.key_generator" => key_generator,
          "action_dispatch.secret_key_base" => secret_key_base,
          "action_dispatch.cookies_rotations" => ActiveSupport::Messages::RotationConfiguration.new
        )

        ActionDispatch::Request.new(env).cookie_jar
      end

      def vite_ruby
        @vite_ruby ||= ViteRuby.new(
          root: Engine.root, public_dir: "public", public_output_dir: "masks-assets",
          mode: "production", auto_build: false, skip_proxy: true
        )
      end

      def key_provider
        return nil unless engine?

        @key_provider ||= ActiveRecord::Encryption::KeyProvider.new(
          ActiveRecord::Encryption::Key.new(key_generator.generate_key("masks/server encryption", 32))
        )
      end
    end
  end
end

require_relative "server/version"
require_relative "server/configuration"
require_relative "server/isolation"
require_relative "server/host"
require_relative "server/tenant_isolation"
require_relative "server/tenancy/job"
require_relative "server/tenancy/middleware"
require_relative "server/engine"
