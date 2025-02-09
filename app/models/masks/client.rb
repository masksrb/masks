# frozen_string_literal: true

module Masks
  class Client < ApplicationRecord
    include SettingsColumn
    include Seedable

    SUBJECT_TYPES = %w[public-uuid public-identifier pairwise-uuid]

    class << self
      def seed(key:, type: nil, name: nil, **attrs)
        return if where(key:).any?

        new(key:, name:, client_type: type, extras: attrs)
      end
    end

    writable(
      key: :string,
      name: :string,
      secret: :string,
      public_url: :string,
      scopes: :json,
      response_types: [:string],
      grant_types: [:string],
      redirect_uris: :string,
      authorization_expires_in: :string,
      id_token_expires_in: :string,
      access_token_expires_in: :string,
      authorization_code_expires_in: :string,
      refresh_token_expires_in: :string,
      client_token_expires_in: :string,
      login_link_expires_in: :string,
      login_link_code_expires_in: :string,
      email_verification_expires_in: :string,
      sso_request_expires_in: :string,
      phone_verification_expires_in: :string,
      identifier_expires_in: :string,
      first_factor_login_link_expires_in: :string,
      first_factor_sso_expires_in: :string,
      first_factor_password_expires_in: :string,
      second_factor_backup_code_expires_in: :string,
      second_factor_phone_expires_in: :string,
      second_factor_otp_expires_in: :string,
      second_factor_webauthn_expires_in: :string,
      internal_token_expires_in: :string,
      onboarding_expires_in: :string,
      sso_providers: [:string],
      allow_nicknames: :boolean,
      allow_emails: :boolean,
      allow_passkeys: :boolean,
      allow_passwords: :boolean,
      allow_login_links: :boolean,
      allow_sso: :boolean,
      allow_profiles: :boolean,
      allow_webauthn: :boolean,
      allow_otp: :boolean,
      allow_backup_codes: :boolean,
      allow_phones: :boolean,
      allow_second_factor: :boolean,
      require_approval: :boolean,
      subject_type: :string,
      sector_identifier: :string,
      pairwise_salt: :string,
      rsa_private_key: :string,
      bg_light: :string,
      bg_dark: :string,
      autofill_redirect_uri: :boolean,
      fuzzy_redirect_uri: :boolean,
    )

    timestamps

    LIFETIME_SETTINGS =
      settings.keys.map { |k| k if k.end_with?("_expires_in") }.compact

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

    encrypts :settings, :secret, :rsa_private_key

    after_initialize :generate_credentials

    generate_key from: :name

    validates :key, :secret, presence: true
    validates :key, uniqueness: true
    validates :subject_type, inclusion: { in: SUBJECT_TYPES }, presence: true
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

    serialize :redirect_uris, coder: JSON
    serialize :response_types, coder: JSON
    serialize :grant_types, coder: JSON
    serialize :scopes, coder: JSON

    attribute :extras
    attribute :client_type

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
    end

    def allow_phones
      !!(setting(:allow_phones) && Masks.installation.phone_adapter&.setup?)
    end

    def second_factor?
      allow_second_factor? &&
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

    def to_param
      key
    end

    def default_redirect_uri
      redirect_uris_a.first
    end

    def redirect_uris_a
      case redirect_uris
      when Array
        redirect_uris
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

    def issuer
      Masks.url
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

    def expires_at(type = nil, custom: nil)
      if custom
        Masks.time.expires_at(custom)
      else
        Masks.time.expires_at(
          setting("#{type.to_s.delete_suffix("_expires_in")}_expires_in"),
        )
      end
    end

    def email_verification_duration
      ChronicDuration.parse(email_verification_expires_in)
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

    private

    def generate_credentials
      return unless new_record?

      install = Masks.installation
      defaults = install.client_defaults
      typed =
        if client_type
          value = install.client_types[client_type.to_s]

          raise MisconfiguredClientError unless value

          value
        end

      self.assign_attributes(defaults.deep_merge(typed || {}))
      self.secret ||= SecureRandom.base58(64)
      self.rsa_private_key ||= OpenSSL::PKey::RSA.generate(2048).to_pem
      self.sector_identifier ||= Masks.url
      self.pairwise_salt ||= SecureRandom.hex(10)
      self.response_types ||= ["code"]
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
