require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Server
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks rack])

    config.action_mailer.delivery_job = "MailDeliveryJob"

    config.masks = ActiveSupport::OrderedOptions.new
    config.masks.attempt_limit = ENV.fetch("MASKS_ATTEMPT_LIMIT", 10).to_i
    config.masks.account_attempt_limit = ENV.fetch("MASKS_ACCOUNT_ATTEMPT_LIMIT", 5).to_i
    config.masks.registration_limit = ENV.fetch("MASKS_REGISTRATION_LIMIT", 10).to_i
    config.masks.recovery_limit = ENV.fetch("MASKS_RECOVERY_LIMIT", 5).to_i
    config.masks.setup_token = ENV["MASKS_SETUP_TOKEN"].presence
    config.masks.public_origin_template = ENV["MASKS_PUBLIC_ORIGIN_TEMPLATE"].presence
    config.masks.tenant = ENV["MASKS_TENANT"].presence
    config.masks.tenants = ENV["MASKS_TENANTS"].to_s.split(/[\s,]+/).reject(&:empty?)
    config.masks.dynamic_client_scopes = ENV["MASKS_DYNAMIC_CLIENT_SCOPES"].presence
    config.masks.mail_from = ENV["MASKS_MAIL_FROM"].presence
    config.masks.invitation_lifetime = ENV.fetch("MASKS_INVITATION_LIFETIME", 7 * 24 * 60 * 60).to_i.seconds
    config.masks.password_reset_lifetime = ENV.fetch("MASKS_PASSWORD_RESET_LIFETIME", 30 * 60).to_i.seconds
    config.masks.email_verification_lifetime = ENV.fetch("MASKS_EMAIL_VERIFICATION_LIFETIME", 2 * 24 * 60 * 60).to_i.seconds

    if config.masks.public_origin_template.nil? && !Rails.env.local?
      raise "MASKS_PUBLIC_ORIGIN_TEMPLATE is required outside development. Without it the " \
            "issuer, the registration endpoint and every emailed link follow the Host header, " \
            "so anyone who can reach this server can have a password reset delivered to theirs."
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    config.active_record.schema_format = :sql

    if ENV["PG_BIN_PATH"].present?
      ENV["PATH"] = "#{ENV['PG_BIN_PATH']}:#{ENV['PATH']}"
    end
  end
end
