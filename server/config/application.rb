require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

require_relative "../lib/error_pages"
require_relative "../lib/request_metrics"
require_relative "../lib/assume_ssl"

module Server
  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks error_pages.rb request_metrics.rb assume_ssl.rb])

    config.i18n.available_locales = Dir[Masks::Server::Engine.root.join("config/locales/*/")].map do |path|
      File.basename(path).to_sym
    end
    config.i18n.default_locale = :en
    config.i18n.fallbacks = true

    config.generators.system_tests = nil

    config.exceptions_app = ErrorPages.new(Rails.public_path)

    config.active_record.schema_format = :sql

    config.action_dispatch.trusted_proxies = Masks::Server::Configuration.trusted_proxies(ENV["MASKS_TRUSTED_PROXIES"])
    config.middleware.insert 0, Masks::Server::Forwarding, config.action_dispatch.trusted_proxies

    if ENV["PG_BIN_PATH"].present?
      ENV["PATH"] = "#{ENV['PG_BIN_PATH']}:#{ENV['PATH']}"
    end
  end
end
