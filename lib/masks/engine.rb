require "vite_rails"
require "active_record/session_store"

module Masks
  class Engine < ::Rails::Engine
    isolate_namespace Masks

    config.autoload_paths << "#{root}/app/graphql"

    delegate :vite_ruby, to: :class

    ENV["VITE_RUBY_ROOT"] ||= root.to_s

    def self.vite_ruby
      @vite_ruby ||= ViteRuby.new(root: root)
    end

    def self.use_secrets(config)
      config.secret_key_base = Masks.env.secrets.secret_key
      config.active_record.encryption.primary_key =
        Masks.env.secrets.encryption_key&.presence
      config.active_record.encryption.deterministic_key =
        Masks.env.secrets.deterministic_key&.presence
      config.active_record.encryption.key_derivation_salt =
        Masks.env.secrets.salt&.presence
    end

    def self.use_sessions(config)
      config.session_store :active_record_store, key: "_masks"
      config.to_prepare do
        config.session_options[
          :expire_after
        ] = Masks::SessionRecord.expire_after if Masks::SessionRecord.expire_after

        # Use the custom session class for consistency, though both should work.
        ActionDispatch::Session::ActiveRecordStore.session_class =
          Masks::SessionRecord

        # This cannot be overridden in Masks::Session, instead it must be here:
        ActiveRecord::SessionStore::Session.table_name = "masks_sessions"
      end
    end

    config.app_middleware.use(
      Rack::Static,
      urls: ["/#{vite_ruby.config.public_output_dir}"],
      root: root.join(vite_ruby.config.public_dir),
    )

    initializer "masks.routing" do |app|
      Masks::Routing.install!

      app.middleware.use Masks::Routing::Middleware
    end

    initializer "masks.vite_proxy" do |app|
      if vite_ruby.run_proxy?
        app.middleware.insert_before 0,
                                     ViteRuby::DevServerProxy,
                                     ssl_verify_none: true,
                                     vite_ruby: vite_ruby
      end
    end
  end
end
