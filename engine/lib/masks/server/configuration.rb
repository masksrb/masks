module Masks
  module Server
    module Configuration
      MODES = %i[server engine].freeze

      module_function

      def defaults
        config = ActiveSupport::OrderedOptions.new
        config.mode = ENV.fetch("MASKS_MODE", "server").to_sym
        config.database = nil
        config.secret = nil
        config.attempt_limit = ENV.fetch("MASKS_ATTEMPT_LIMIT", 10).to_i
        config.account_attempt_limit = ENV.fetch("MASKS_ACCOUNT_ATTEMPT_LIMIT", 5).to_i
        config.registration_limit = ENV.fetch("MASKS_REGISTRATION_LIMIT", 10).to_i
        config.recovery_limit = ENV.fetch("MASKS_RECOVERY_LIMIT", 5).to_i
        config.device_code_limit = ENV.fetch("MASKS_DEVICE_CODE_LIMIT", 30).to_i
        config.setup_token = ENV["MASKS_SETUP_TOKEN"].presence
        config.themes_path = ENV["MASKS_THEMES_PATH"].presence
        config.docs_url = ENV.fetch("MASKS_DOCS_URL", "https://masks.pages.dev")
        config.public_origin_template = ENV["MASKS_PUBLIC_ORIGIN_TEMPLATE"].presence
        config.tenant = ENV["MASKS_TENANT"].presence
        config.tenants = ENV["MASKS_TENANTS"].to_s.split(/[\s,]+/).reject(&:empty?)
        config.dynamic_client_scopes = ENV["MASKS_DYNAMIC_CLIENT_SCOPES"].presence
        config.named_by = ENV["MASKS_NAMED_BY"].presence
        config.dynamic_registration = ENV["MASKS_DYNAMIC_REGISTRATION"].presence
        config.browsers_only = ENV["MASKS_BROWSERS_ONLY"].presence
        config.blocked_agents = ENV["MASKS_BLOCKED_AGENTS"].presence
        config.mail_from = ENV["MASKS_MAIL_FROM"].presence
        config.smtp_address = ENV["MASKS_SMTP_ADDRESS"].presence
        config.smtp_settings = smtp_settings(config.smtp_address)
        config.invitation_lifetime = ENV.fetch("MASKS_INVITATION_LIFETIME", 7 * 24 * 60 * 60).to_i.seconds
        config.password_reset_lifetime = ENV.fetch("MASKS_PASSWORD_RESET_LIFETIME", 30 * 60).to_i.seconds
        config.email_verification_lifetime = ENV.fetch("MASKS_EMAIL_VERIFICATION_LIFETIME", 2 * 24 * 60 * 60).to_i.seconds
        config
      end

      def smtp_settings(address)
        return nil if address.nil?

        port = ENV.fetch("MASKS_SMTP_PORT", 587).to_i
        implicit_tls = ENV.fetch("MASKS_SMTP_TLS", port == 465 ? "true" : "false") == "true"

        {
          address: address,
          port: port,
          user_name: ENV["MASKS_SMTP_USERNAME"].presence,
          password: ENV["MASKS_SMTP_PASSWORD"].presence,
          authentication: ENV.fetch("MASKS_SMTP_AUTHENTICATION", "plain").to_sym,
          domain: ENV["MASKS_SMTP_DOMAIN"].presence,
          tls: implicit_tls,
          enable_starttls: !implicit_tls,
          openssl_verify_mode: OpenSSL::SSL::VERIFY_PEER,
          open_timeout: 10,
          read_timeout: 10
        }.compact
      end

      def validate!(config, local:, building:)
        unless MODES.include?(config.mode)
          raise "masks runs in server or engine mode, and config.masks.mode is #{config.mode.inspect}."
        end

        if config.named_by && !%w[nickname email either].include?(config.named_by)
          raise "MASKS_NAMED_BY is #{config.named_by.inspect}, and the only things an " \
                "account can be named by are a nickname, an email address, or either one. " \
                "Set it to nickname, email or either, or leave it unset and let the first-run " \
                "screen decide."
        end

        if config.dynamic_registration && !%w[off anything bounded].include?(config.dynamic_registration)
          raise "MASKS_DYNAMIC_REGISTRATION is #{config.dynamic_registration.inspect}. " \
                "Dynamic registration is off, on for anything a manager does not have to grant, " \
                "or on and bounded by MASKS_DYNAMIC_CLIENT_SCOPES. Set it to off, anything or " \
                "bounded, or leave it unset and let the first-run screen decide."
        end

        return if local || building

        if config.mail_from && config.smtp_address.nil?
          raise "MASKS_MAIL_FROM is set but MASKS_SMTP_ADDRESS is not. Mail would be handed to a " \
                "local sendmail that is not there, and every invitation and password reset would " \
                "be dropped without an error anyone sees."
        end

        if config.public_origin_template.nil?
          raise "MASKS_PUBLIC_ORIGIN_TEMPLATE is required outside development. Without it the " \
                "issuer, the registration endpoint and every emailed link follow the Host header, " \
                "so anyone who can reach this server can have a password reset delivered to theirs."
        end

        if config.setup_token && config.setup_token.length < 24
          raise "MASKS_SETUP_TOKEN is #{config.setup_token.length} characters, and at least 24 are " \
                "required outside development. Whoever holds it creates the first account of every " \
                "tenant that has none, and that account manages the tenant."
        end

        if config.mode == :engine && config.database.nil?
          raise "masks in engine mode needs a database of its own. Set config.masks.database to " \
                "the name of a database.yml entry whose role cannot bypass row-level security."
        end
      end
    end
  end
end
