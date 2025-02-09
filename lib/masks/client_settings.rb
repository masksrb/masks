module Masks
  module ClientSettings
    extend ActiveSupport::Concern

    included do
      include Masks::Seedable
      include Masks::Settings

      setting :name, :string
      setting :key, :string
      setting :type, :string
      setting :secret, :string, secret: true
      setting :internal, :boolean, default: false
      setting :pkce, :boolean, default: false
      setting :issuer, :string, default: -> { default_issuer }
      setting :allowed_scopes, [:string]
      setting :required_scopes, [:string]
      setting :grant_types, [:string]
      setting :response_types, [:string], default: -> { ["code"] }
      setting :redirect_uris, :json
      setting :default_redirect_uri,
              :string,
              default: -> { redirect_uris_a&.first }
      setting :public_url, :string
      setting :styles_url, :string
      setting :terms_url, :string, default: -> { Masks.conf.terms_url }
      setting :rsa_private_key, :string, secret: true
      setting :require_approval, :boolean, default: -> { !internal? }
      setting :sector_identifier,
              :string,
              default: -> { default_sector_identifier }
      setting :subject_type, :string, default: "pairwise-uuid"
      setting :id_token_duration, :string, default: "6 hours"
      setting :access_token_duration, :string, default: "6 hours"
      setting :authorization_code_duration, :string, default: "10 minutes"
      setting :refresh_token_duration, :string, default: "1 day"
      setting :client_token_duration, :string, default: "12 hours"
      setting :internal_token_duration, :string, default: "1 day"
      setting :login_attempt_duration, :string, default: "1 hour"
      setting :login_link_duration, :string, default: "15 minutes"
      setting :verified_email_duration, :string, default: "1 year"
      setting :phone_verification_duration, :string, default: "15 minutes"
      setting :sso_request_duration, :string, default: "30 minutes"
      setting :sso_login_duration, :string, default: "6 hours"
      setting :email_login_duration, :string, default: "12 hours"
      setting :password_login_duration, :string, default: "1 day"
      setting :signup_login_duration, :string, default: "1 hour"
      setting :backup_code_2fa_duration, :string, default: "3 hours"
      setting :phone_2fa_duration, :string, default: "2 hours"
      setting :otp_2fa_duration, :string, default: "2 hours"
      setting :webauthn_2fa_duration, :string, default: "2 hours"
      setting :actor_duration, :string, default: "1 week"
      setting :onboarded_profile_duration, :string, default: "1 year"
      setting :allow_login, :boolean, default: true
      setting :allow_signup, :boolean, default: true
      setting :allow_nicknames, :boolean, default: true
      setting :require_nickname, :boolean, default: true
      setting :allow_emails, :boolean, default: true
      setting :require_email, :boolean, default: false
      setting :allow_passwords, :boolean, default: true
      setting :require_password, :boolean, default: true
      setting :allow_login_links, :boolean, default: true
      setting :allow_factor2, :boolean, default: true
      setting :allow_otp, :boolean, default: true
      setting :allow_phones, :boolean, default: true
      setting :allow_webauthn, :boolean, default: true
      setting :allow_backup_codes, :boolean, default: true
      setting :allow_sso, :boolean, default: true
      setting :allow_profiles, :boolean, default: true
      setting :allow_discovery, :boolean, default: false

      timestamps
    end

    def scopes
      (allowed_scope.to_a + required_scope.to_a).uniq
    end

    def required_scope
      Masks::Scopes.new(self, :required_scopes)
    end

    def allowed_scope
      Masks::Scopes.new(self, :allowed_scopes)
    end

    def default_issuer
      nil
    end

    def default_sector_identifier
      Masks.conf.url
    end
  end
end
