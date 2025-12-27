# frozen_string_literal: true

module Masks
  class Engine < ::Rails::Engine
    isolate_namespace Masks

    config.autoload_paths << "#{root}/app/graphql"

    delegate :vite_ruby, to: :class

    ENV['VITE_RUBY_ROOT'] ||= root.to_s

    def self.vite_ruby
      @vite_ruby ||= ViteRuby.new(root: root)
    end

    config.to_prepare do
      Masks.reset!
    end

    initializer 'masks.middleware' do |app|
      app.middleware.use Masks::RequestMiddleware
    end

    initializer 'masks.chronic_duration' do |_app|
      ChronicDuration.raise_exceptions = true
    end

    initializer "masks.static" do |_app|
      config.app_middleware.use(Rack::Static,
        urls: ["/#{vite_ruby.config.public_output_dir}"],
        root: root.join(vite_ruby.config.public_dir),
      )
    end

    initializer "masks.vite_proxy" do |app|
      next unless vite_ruby.run_proxy?

      app.middleware.insert_before 0,
        ViteRuby::DevServerProxy,
        ssl_verify_none: true,
        vite_ruby:
    end
  end
end
