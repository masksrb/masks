# frozen_string_literal: true

module Masks
  class Actor < ApplicationRecord
    include Cleanable
    include ScopesColumn
    include SettingsColumn
    include Seedable

    self.table_name = "masks_actors"

    class << self
      def identify(identifier = nil, **opts)
        unless identifier&.presence
          identifier = opts.except(:required)
          opts = opts.slice(:required)
        end

        case identifier
        when String
          actor =
            if identifier&.include?("@")
              from_login_email(identifier)
            else
              find_or_initialize_by(nickname: identifier)
            end

          if opts[:required]
            actor if actor.persisted?
          else
            actor
          end
        when Hash
          if opts[:required]
            find_by(identifier)
          else
            find_or_initialize_by(identifier)
          end
        end
      end

      def from_login_email(address)
        email = Masks::Email.for_login.where(address:).first
        email&.actor || with_login_email(address)
      end

      def with_login_email(address)
        Masks::Actor
          .new(identifier: address)
          .tap { |a| a.emails.build(address:).for_login }
      end

      def seed(key:, password:, nickname: nil, scopes: nil, email: nil, **attrs)
        record = identify(nickname || email || { key: })

        return if record.persisted?

        record.nickname ||= nickname || key

        if email&.present?
          record.emails.build(address: email, group: Masks::Email::LOGIN_GROUP)
        end

        record.assign_attributes(attrs.merge(key:))
        record.password = password
        record.assign_scopes(*scopes)
        record
      end
    end

    writable(
      key: :string,
      name: :string,
      uuid: :string,
      nickname: :string,
      password: :string,
      scopes: [:string],
      tz: :string,
      defined: true,
    )

    timestamps

    cleanup :last_login_at do
      Masks.installation.duration(:actors, :inactive)
    end

    generate_key from: :identifier

    has_many :emails, class_name: "Masks::Email", autosave: true
    has_many :phones, class_name: "Masks::Phone", autosave: true
    has_many :tokens, class_name: "Masks::Token", autosave: true
    has_many :clients, class_name: "Masks::Client", through: :tokens
    has_many :devices,
             -> { distinct },
             class_name: "Masks::Device",
             through: :tokens

    has_many :login_links, class_name: "Masks::LoginLink", autosave: true
    has_many :hardware_keys, class_name: "Masks::HardwareKey", autosave: true
    has_many :otp_secrets, class_name: "Masks::OtpSecret", autosave: true
    has_many :single_sign_ons, class_name: "Masks::SingleSignOn", autosave: true

    has_one_attached :avatar do |attachable|
      attachable.variant :preview, resize_to_limit: [350, 350]
    end

    has_secure_password validations: false

    attribute :signup
    attribute :session
    attribute :new_password

    attr_reader :manager

    after_initialize :generate_defaults

    validates :identifier_type, presence: true
    validates :key, presence: true, uniqueness: true
    validates :nickname, uniqueness: true, if: :nickname
    validates :nickname,
              format: {
                with: ->(a) { a.nickname_format },
              },
              if: :nickname_format
    validate :validates_password,
             if: -> { password || password_challenge || new_password }
    validate :validates_backup_codes, if: :backup_codes
    validates_associated :emails
    validates :disallowed, absence: true

    serialize :backup_codes, coder: JSON

    def session_key
      key
    end

    def tz
      super || Masks.installation.timezone
    end

    def onboarded!
      touch(:onboarded_at)
    end

    def onboarded?
      onboarded_at
    end

    def unverified_email?
      emails.verified_for_login.none?
    end

    def reset_password
      self.password_digest = nil
      self.password_changed_at = nil
    end

    def change_password(v, challenge:)
      return unless password_changeable?

      self.password_challenge = challenge || ""
      self.new_password = v
    end

    def overwrite_password(v)
      self.password = v
    end

    def password_changeable?
      return true unless password_changed_at && password_settings[:cooldown]

      password_changeable_at < Time.now.utc
    rescue => e
      true
    end

    def password_changeable_at
      return unless password_settings[:cooldown] && password_changed_at

      Masks.time.expires_at(
        password_settings[:cooldown],
        after: password_changed_at,
      )
    end

    def public_id
      key
    end

    def identifier_type
      if nickname
        nickname_type
      elsif login_email&.valid?
        email_type
      end
    end

    attr_accessor :disallowed
    attr_writer :identifier

    def identifier
      @identifier ||=
        case identifier_type
        when email_type
          login_email.address
        when nickname_type
          nickname
        end
    end

    def avatar_created_at
      avatar.created_at if avatar&.attached?
    end

    def avatar_url
      rails_storage_proxy_url(avatar.variant(:preview)) if avatar&.attached?
    end

    def identicon_id
      @identicon_id ||= (Digest::MD5.hexdigest("identicon-#{key}") if key)
    end

    def login_email
      persisted? ? login_emails.first : emails.select(&:for_login?).first
    end

    def login_emails
      emails.for_login
    end

    def to_param
      key
    end

    def second_factor?
      enabled_second_factor_at.present?
    end

    def review_second_factor?
      second_factor? && !backup_codes&.any?
    end

    def enable_second_factor!
      return if second_factors.none? || backup_codes&.blank?

      touch(:enabled_second_factor_at)
    end

    def disable_second_factor!
      update!(enabled_second_factor_at: nil)
    end

    def second_factors
      @second_factors ||= [
        *(phones.all.to_a),
        *(hardware_keys.all.to_a),
        *(otp_secrets.all.to_a),
      ].compact
    end

    def verify_backup_code(code)
      return false unless code && backup_codes&.any?

      hash = Digest::SHA256.hexdigest(code)

      if backup_codes.include?(hash)
        backup_codes.delete(hash)
        save
      else
        false
      end
    end

    def save_backup_codes(codes, **args)
      @new_backup_codes = true

      self.backup_codes = codes

      run_validations = args.key?(:validate) ? args[:validate] : true

      return if run_validations && !valid?

      self.saved_backup_codes_at = Time.now.utc
      self.backup_codes = codes.map { |code| Digest::SHA256.hexdigest(code) }

      save(validate: run_validations)
    ensure
      @new_backup_codes = false
    end

    def reset_backup_codes
      self.backup_codes = nil
      self.saved_backup_codes_at = nil
    end

    def nickname_format
      if nickname && nickname_settings[:format]
        Regexp.new(nickname_settings[:format])
      end
    end

    def manager=(v)
      @manager = v

      if v
        assign_scopes(Masks::Scopes::MANAGE)
      else
        remove_scopes(Masks::Scopes::MANAGE)
      end
    end

    private

    def generate_defaults
      self.uuid ||= SecureRandom.uuid
      self.webauthn_id ||= WebAuthn.generate_user_id

      assign_scopes(*Masks.installation.setting(:actors, :defaults, :scopes, default: []))
    end

    def validates_length(value, key:, min_chars:, max_chars:)
      return unless value

      if min_chars && value.length < min_chars
        errors.add(key, :too_short, count: min_chars)
      elsif max_chars && value.length > max_chars
        errors.add(key, :too_long, count: max_chars)
      end
    end

    def validates_nickname
      return unless nickname

      validates_length(
        nickname,
        key: :nickname,
        **nickname_settings.slice(:min_chars, :max_chars),
      )
    end

    def validates_password
      if password_challenge && !authenticate(password_challenge)
        return errors.add(:password_challenge, :invalid)
      end

      self.password = self.new_password if new_password && password_challenge

      return unless password

      if password_settings
        validates_length(
          password,
          key: :password,
          **password_settings.slice(:min_chars, :max_chars),
        )
      end

      if !password_changeable?
        time =
          ApplicationController.helpers.distance_of_time_in_words(
            Time.current,
            password_changeable_at,
          )

        return errors.add(:password, :unchangeable, time:)
      end

      self.password_changed_at = Time.current if persisted?
    end

    def validates_backup_codes
      opts = backup_code_settings

      return unless backup_codes && opts && @new_backup_codes

      if opts[:total]
        unless backup_codes.length == opts[:total]
          errors.add(:backup_codes, :length, total: opts[:total])
        end
      end

      backup_codes.each do |code|
        validates_length(
          code,
          key: :backup_codes,
          **opts.slice(:min_chars, :max_chars),
        )
      end
    end

    def nickname_settings
      @nickname_settings ||= Masks.installation.nicknames
    end

    def password_settings
      @password_settings ||= Masks.installation.passwords
    end

    def backup_code_settings
      @backup_code_settings ||= Masks.installation.backup_codes
    end

    def email_type
      "email"
    end

    def nickname_type
      "nickname"
    end
  end
end
