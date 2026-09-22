module Masks
  module Server
    class Engine < ::Rails::Engine
      isolate_namespace Masks::Server

      config.before_configuration do |app|
        app.config.masks = Configuration.defaults
      end

      middleware.use Tenancy::Middleware

      config.after_initialize do |app|
        app.config.masks.themes_path ||= app.root.join("themes").to_s

        Configuration.validate!(
          app.config.masks,
          local: ::Rails.env.local?,
          building: ENV["SECRET_KEY_BASE_DUMMY"].present?
        )

        middleware.insert_before Tenancy::Middleware, Isolation if app.config.masks.mode == :engine
      end

      initializer "masks_server.static" do |app|
        app.middleware.use Rack::Static,
                           urls: %w[/masks-public /masks-assets],
                           root: root.join("public").to_s,
                           header_rules: [
                             [ :all, { "cache-control" => "public, max-age=3600" } ],
                             [ "/masks-assets", { "cache-control" => "public, max-age=31536000, immutable" } ]
                           ]
      end

      initializer "masks_server.migrations", after: :load_config_initializers do |app|
        next if app.config.masks.mode == :engine
        next if app.root.to_s == root.to_s

        config.paths["db/migrate"].expanded.each { |path| app.config.paths["db/migrate"] << path }
      end
    end
  end
end
