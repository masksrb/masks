require "vite_rails"
require "active_record/session_store"
require_relative "../masks"

module Masks
  class Engine < ::Rails::Engine
    isolate_namespace Masks

    config.autoload_paths << "#{root}/app/graphql"

    delegate :vite_ruby, to: :class

    ENV["VITE_RUBY_ROOT"] ||= root.to_s

    def self.vite_ruby
      @vite_ruby ||= ViteRuby.new(root: root)
    end

    initializer "masks.chronic_duration" do |app|
      ChronicDuration.raise_exceptions = true if Masks.mode.server?
    end

    initializer "masks.webauthn" do |app|
      next unless Masks.mode.server?

      WebAuthn.configure do |config|
        config.allowed_origins = Masks.conf.webauthn_origins
        config.rp_name = Masks.conf.webauthn_name
        config.algorithms = Masks.conf.webauthn_algos
        config.silent_authentication = true
        config.attestation_root_certificates_finders = Masks::Shims::Fido
      end

      FidoMetadata.configure { |config| config.cache_backend = Rails.cache }
    end

    initializer "masks.static" do |app|
      if Masks.mode.server?
        config.app_middleware.use(
          Rack::Static,
          urls: ["/#{vite_ruby.config.public_output_dir}"],
          root: root.join(vite_ruby.config.public_dir),
        )
      end
    end

    initializer "masks.phonelib" do |app|
      Phonelib.default_country = Masks.conf.phone_country if Masks.mode.server?
    end

    initializer "masks.routing" do |app|
      Masks::Routing.install!
    end

    initializer "masks.vite_proxy" do |app|
      next unless Masks.mode.server? && vite_ruby.run_proxy?

      app.middleware.insert_before 0,
                                   ViteRuby::DevServerProxy,
                                   ssl_verify_none: true,
                                   vite_ruby: vite_ruby
    end
  end
end
