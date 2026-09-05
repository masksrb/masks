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

module Server
  class Application < Rails::Application
    config.load_defaults 8.1

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

    if config.masks.public_origin_template.nil? && !Rails.env.local? &&
       ENV["SECRET_KEY_BASE_DUMMY"].blank?
      raise "MASKS_PUBLIC_ORIGIN_TEMPLATE is required outside development. Without it the " \
            "issuer, the registration endpoint and every emailed link follow the Host header, " \
            "so anyone who can reach this server can have a password reset delivered to theirs."
    end

    config.generators.system_tests = nil

    config.active_record.schema_format = :sql

    if ENV["PG_BIN_PATH"].present?
      ENV["PATH"] = "#{ENV['PG_BIN_PATH']}:#{ENV['PATH']}"
    end
  end
end
