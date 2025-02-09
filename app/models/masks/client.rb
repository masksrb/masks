# frozen_string_literal: true

module Masks
  class Client < ApplicationRecord
    include SettingsColumn
    include Seedable

    class << self
      def seed(key:, type: nil, name: nil, **attrs)
        return if where(key:).any?

        new(key:, name:, client_type: type, extras: attrs)
      end
    end

    setting :name, :string
    setting :key, :string
    setting :type, :string
    setting :secret, :string, secret: true
    setting :internal, :boolean, default: false
    setting :pkce, :boolean, default: false
    setting :issuer, :string, default: -> { default_issuer }
    setting :scopes, :json, default: -> { {} }
    setting :allowed_scopes, [:string], key: %i[scopes allowed]
    setting :required_scopes, [:string], key: %i[scopes required]
    setting :grant_types, [:string]
    setting :response_types, [:string], default: -> { ["code"] }
    setting :redirect_uris, :json
    setting :styles, :string
    setting :styles_url, :string
    setting :autofill_redirect_uri, :boolean, default: false
    setting :fuzzy_redirect_uri, :boolean, default: false
    setting :default_redirect_uri,
            :string,
            default: -> { redirect_uris_a&.first }
    setting :public_url, :string
    setting :rsa_private_key, :string, secret: true
    setting :require_approval, :boolean, default: -> { !internal? }
    setting :sector_identifier, :string, default: -> { Masks.conf.url }
    setting :pairwise_salt, :string
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
    setting :backup_code_2fa_duration, :string, default: "3 hours"
    setting :phone_2fa_duration, :string, default: "2 hours"
    setting :otp_2fa_duration, :string, default: "2 hours"
    setting :webauthn_2fa_duration, :string, default: "2 hours"
    setting :actor_duration, :string, default: "1 week"
    setting :onboarded_profile_duration, :string, default: "1 year"
    setting :allow_nicknames, :boolean, default: true
    setting :allow_emails, :boolean, default: true
    setting :allow_passwords, :boolean, default: true
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

    LIFETIME_SETTINGS =
      settings.keys.map { |k| k if k.end_with?("_duration") }.compact

    CODE_CHALLENGE_METHODS = %w[S256 plain]
    DEFAULT_KEY = "default"

    scope :internal, -> { where(internal: true) }
    scope :oauth, -> { where(internal: false) }

    self.table_name = "masks_clients"

    has_one_attached :logo do |attachable|
      attachable.variant :preview,
                         resize_to_limit: [500, 500],
                         preprocessed: true
    end

    validates :name, presence: true

    encrypts :settings, :rsa_private_key

    after_initialize :generate_credentials

    generate_key from: :name

    validates :key, :secret, presence: true
    validates :key, uniqueness: true
    validates :subject_type,
              inclusion: {
                in: -> { Masks.conf.subject_types },
              },
              presence: true
    validate :validate_expiries

    has_many :tokens, class_name: "Masks::Token", inverse_of: :client
    has_many :login_links, class_name: "Masks::LoginLink"
    has_many :actors,
             -> { distinct },
             class_name: "Masks::Actor",
             through: :tokens
    has_many :devices,
             -> { distinct },
             class_name: "Masks::Device",
             through: :tokens
    has_many :client_providers,
             class_name: "Masks::ClientProvider",
             autosave: true

    attribute :extras
    attribute :client_type

    def public_json
      {
        id: key,
        logo: logo_url,
        name:,
        allow_emails:,
        allow_nicknames:,
        allow_passwords:,
        allow_sso:,
        allow_login_links:,
        allow_factor2:,
        allow_backup_codes:,
        allow_phones:,
        allow_webauthn:,
        allow_profiles:,
        allow_otp:,
      }
    end

    def require_scopes=(val)
      scope.require!(val)
    end

    def allow_scopes=(val)
      scope.allow!(val)
    end

    def remove_scopes=(val)
      scope.remove!(val)
    end

    def allow_scopes
      scopes
    end

    def remove_scopes
      scopes
    end

    def require_scopes
      scopes
    end

    def supports_oauth?
      !internal?
    end

    def session_key
      key
    end

    def identify(identifier)
      if identifier&.include?("@") && allow_emails?
        Actor.from_login_email(identifier)
      elsif allow_nicknames?
        Actor.find_or_initialize_by(nickname: identifier)
      else
        Actor.new(identifier:, disallowed: true)
      end
    end

    def enable_second_factor!
      update!(
        allow_otp: true,
        allow_phones: true,
        allow_backup_codes: true,
        allow_webauthn: true,
        allow_2fa: true,
      )
    end

    def disable_second_factor!
      disable_second_factor
      save!
    end

    def disable_second_factor
      self.allow_otp = false
      self.allow_phones = false
      self.allow_backup_codes = false
      self.allow_webauthn = false
      self.allow_factor2 = false
    end

    def telephony
      @telephony ||= Masks::Telephony.verifier(client)
    end

    def second_factor?
      allow_factor2? &&
        (allow_otp? || allow_phones? || allow_backup_codes? || allow_webauthn?)
    end

    def provider?(provider)
      allow_sso? && provider&.usable?
    end

    def assign_provider=(v)
      client_providers.find_or_initialize_by(provider: Masks.provider(v))
    end

    def remove_provider=(v)
      provider = Masks.provider(v)

      client_providers.each do |record|
        record.mark_for_destruction if record.provider_id == provider.id
      end
    end

    def providers
      return [] unless allow_sso?

      available_providers.filter { |provider| provider?(provider) }
    end

    def available_providers
      Masks::Provider.common.or(
        Masks::Provider.enabled.where(
          id: client_providers.distinct(:provider_id).pluck(:provider_id),
        ),
      )
    end

    def scope
      @scope ||= ClientScope.new(self)
    end

    def logo_url
      rails_storage_proxy_url(logo.variant(:preview)) if logo&.attached?
    end

    def logo_file=(file)
      logo.attach(file)
    end

    def to_param
      key
    end

    def redirect_uris_a
      case redirect_uris
      when Array
        redirect_uris.map { |s| s.split("\n") }.flatten
      when String
        redirect_uris.split("\n")
      else
        []
      end
    end

    def valid_response_type?(value)
      return false unless value&.present?

      response_types.include?(value)
    end

    def valid_grant_type?(value)
      return false unless value&.present?

      grant_types.include?(value.to_s)
    end

    def valid_redirect_uri?(uri)
      uri = uri.to_s

      return false if uri.start_with?("/") && !internal?

      if fuzzy_redirect_uri?
        redirect_uris_a.any? do |redirect_uri|
          Fuzzyurl.matches?(Fuzzyurl.mask(redirect_uri), uri)
        end
      else
        redirect_uris_a.include?(uri)
      end
    end

    def valid_pkce_request?(response_type:, challenge:, method:)
      if pkce? && response_type.include?("code")
        challenge&.present? && CODE_CHALLENGE_METHODS.include?(method)
      else
        true
      end
    end

    def subject_types
      [subject_type.split("-").first] # one of pairwise or public
    end

    def kid
      :default
    end

    def private_key
      OpenSSL::PKey::RSA.new(rsa_private_key)
    end

    delegate :public_key, to: :private_key

    def subject(actor)
      type, attr = subject_type.split("-")
      value =
        case attr
        when "identifier"
          actor.identifier
        when "uuid"
          actor.key
        end

      case type
      when "public"
        value
      else
        "pairwise"
        Digest::SHA256.hexdigest(
          [sector_identifier, value, pairwise_salt].join("+"),
        )
      end
    end

    def audience
      key
    end

    def auto_consent?
      internal? || !require_approval?
    end

    def duration(type = nil)
      Masks.time.duration(
        setting("#{type.to_s.delete_suffix("_duration")}_duration"),
      )
    end

    def expires_at(type = nil, custom: nil)
      if custom
        Masks.time.expires_at(custom)
      else
        Masks.time.expires_at(
          setting("#{type.to_s.delete_suffix("_duration")}_duration"),
        )
      end
    end

    def email_verification_duration
      ChronicDuration.parse(email_verification_duration)
    end

    def oauth_params(params)
      params =
        params.merge(
          "client_id" => key,
          "scope" => scope.minimum(params["scope"]).join(" "),
        )

      if internal?
        { "redirect_uri" => default_redirect_uri }.merge(params).merge(
          "response_type" => "code",
        )
      else
        params
      end
    end

    def logout
      nil
    end

    def valid_secret?(secret)
      return false unless secret&.present? && self.secret&.present?

      ActiveSupport::SecurityUtils.secure_compare(secret, self.secret)
    end

    def bearer_token!(scopes:)
      ClientToken.create!(client: self, scopes:).to_bearer_token
    end

    def styles_url
      Rails.application.routes.url_helpers.masks_client_css_url(
        self,
        **Masks.default_url_options,
      )
    end

    private

    def default_issuer
      Rails.application.routes.url_helpers.masks_client_issuer_url(
        self,
        **Masks.default_url_options,
      )
    rescue StandardError
      Masks.conf.url
    end

    def generate_credentials
      return unless new_record?

      defaults = Masks.conf.client_defaults
      typed = Masks.conf.client_types[client_type.to_s] if client_type

      self.secret ||= SecureRandom.base58(64)
      self.pairwise_salt ||= SecureRandom.hex(10)
      self.rsa_private_key ||= OpenSSL::PKey::RSA.generate(2048).to_pem
      self.assign_attributes(defaults) if defaults
      self.assign_attributes(typed) if typed
      self.assign_attributes(extras) if extras
    end

    def validate_expiries
      LIFETIME_SETTINGS.each do |key|
        value = setting(key)

        raise "invalid" unless value && ChronicDuration.parse(value)
      rescue StandardError
        errors.add(key, :invalid)
      end
    end
  end
end
