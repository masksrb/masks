# frozen_string_literal: true

module Masks
  class Client < ApplicationRecord
    self.table_name = "masks_clients"

    include ClientSettings
    include Seedable

    serialize :settings, coder: JSON
    encrypts :settings, :rsa_private_key

    class << self
      def seed(key:, type: nil, name: nil, **attrs)
        return if where(key:).any?

        new(key:, name:, client_type: type, extras: attrs)
      end

      def duration_settings
        settings
          .keys
          .map { |k| k.to_s.end_with?("_duration") ? k : nil }
          .compact
      end
    end

    setting :autofill_redirect_uri, :boolean, default: false
    setting :fuzzy_redirect_uri, :boolean, default: false
    setting :pairwise_salt, :string

    CODE_CHALLENGE_METHODS = %w[S256 plain]
    DEFAULT_KEY = "default"

    scope :internal, -> { where(internal: true) }
    scope :oauth, -> { where(internal: false) }

    has_one_attached :light_logo do |attachable|
      attachable.variant :preview,
                         resize_to_limit: [500, 500],
                         preprocessed: true
    end

    has_one_attached :dark_logo do |attachable|
      attachable.variant :preview,
                         resize_to_limit: [500, 500],
                         preprocessed: true
    end

    has_one_attached :styles

    validates :name, presence: true

    after_initialize :generate_credentials

    generate_key from: :name

    validates :key, :secret, presence: true
    validates :key, uniqueness: true
    validates :subject_type,
              inclusion: {
                in: -> { Masks.mode.subject_types },
              },
              presence: true
    validates :styles_url, url: true, if: -> { styles_url&.present? }
    validates :terms_url, url: true, if: -> { terms_url&.present? }
    validate :validate_expiries

    has_many :tokens, class_name: "Masks::Token", inverse_of: :client
    has_many :login_links, class_name: "Masks::LoginLink"
    has_many :actors,
             -> { distinct },
             class_name: Masks.mode.class_name(:actor),
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

    def profile_url(actor, redirect_uri:)
      if internal?
        Masks.rails_url(
          :masks_login,
          self,
          prompt: "profile",
          login_hint: actor.identifier,
          redirect_uri:,
        )
      end
    end

    def public_json
      {
        id: key,
        light_logo: light_logo_url,
        dark_logo: dark_logo_url,
        name:,
        terms_url:,
        allow_login:,
        allow_signup:,
        allow_profiles:,
        allow_emails:,
        allow_nicknames:,
        allow_passwords:,
        allow_sso:,
        allow_login_links:,
        allow_factor2:,
        allow_backup_codes:,
        allow_phones:,
        allow_webauthn:,
        allow_otp:,
      }
    end

    def require_scopes=(val)
      self.required_scopes = Masks::Scopes.combine(required_scopes, val)
      self.allowed_scopes = Masks::Scopes.filter(allowed_scopes, val)
    end

    def allow_scopes=(val)
      self.required_scopes = Masks::Scopes.filter(required_scopes, val)
      self.allowed_scopes = Masks::Scopes.combine(allowed_scopes, val)
    end

    def remove_scopes=(val)
      self.required_scopes = Masks::Scopes.filter(required_scopes, val)
      self.allowed_scopes = Masks::Scopes.filter(allowed_scopes, val)
    end

    def supports_oauth?
      !internal?
    end

    def session_key
      key
    end

    def styles_url
      setting = setting(:styles_url)

      return setting if setting

      Masks.storage_url(styles) if styles&.attached? && !styles&.new_record?
    end

    def remove_styles!
      self.styles_url = nil
      self.styles.detach if self.styles.attached?
    end

    def find_token(secret:, device:)
      InternalToken.find_by(device:, client: self, secret:) if internal?
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

    def signup(**opts)
      attrs = {}

      {
        name: :allow_profiles?,
        email: :allow_emails?,
        nickname: :allow_nicknames?,
        password: :allow_passwords?,
      }.each { |k, test| attrs[k] = opts[k] if send(test) }

      Masks.actors.seed(key: nil, current_client: self, **attrs)
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

    def light_logo_url
      if light_logo&.attached?
        return Masks.storage_url(light_logo)
      end
    end

    def dark_logo_url
      if dark_logo&.attached?
        return Masks.storage_url(dark_logo)
      end
    end

    def has_logo?
      light_logo_url || dark_logo_url
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
          "scope" => required_scope.combine(params["scope"]).join(" "),
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

    def default_issuer
      Rails.application.routes.url_helpers.masks_client_issuer_url(
        self,
        **Masks.default_url_options,
      )
    rescue StandardError
      Masks.mode.url
    end

    def generate_credentials
      return unless new_record?

      typed = Masks.mode.client_types[client_type.to_s] if client_type

      self.secret ||= SecureRandom.base58(64)
      self.pairwise_salt ||= SecureRandom.hex(10)
      self.rsa_private_key ||= OpenSSL::PKey::RSA.generate(2048).to_pem
      self.assign_attributes(typed) if typed
      self.assign_attributes(extras) if extras
    end

    def validate_expiries
      self.class.duration_settings.each do |key|
        value = setting(key)

        raise "invalid" unless value && ChronicDuration.parse(value)
      rescue StandardError
        errors.add(key, :invalid)
      end
    end
  end
end
