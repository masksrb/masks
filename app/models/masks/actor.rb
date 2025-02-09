# frozen_string_literal: true

module Masks
  class Actor < ApplicationRecord
    self.table_name = "masks_actors"

    attribute :current_client

    include Masks::ActorSettings

    setting :password, :string, defined: true

    serialize :settings, coder: JSON
    serialize :scopes, coder: JSON

    validates :nickname,
              presence: true,
              if: -> { current_client&.require_nickname? }
    validates :login_email,
              presence: true,
              if: -> { current_client&.require_email? }
    validates :password_digest,
              presence: true,
              if: -> { current_client&.require_password? }

    include Cleanable

    cleanup :last_login_at do
      Masks.conf.duration(:actor_inactive)
    end

    class << self
      def identify(identifier = nil, **opts)
        unless identifier&.presence
          identifier = opts.except(:required, :signup)
          opts = opts.slice(:required, :signup)
        end

        if opts[:signup]
          return(
            new(**identifier.slice(:nickname, :email, :password, :login_email))
          )
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
        email&.actor || new(identifier: address, login_email: address)
      end

      def seed(
        key: nil,
        password: nil,
        nickname: nil,
        scopes: nil,
        email: nil,
        **attrs
      )
        record = identify(nickname || email || { key: })

        return if record.persisted?

        record.nickname ||= nickname || key
        record.login_email = email if email&.present?

        record.assign_attributes(attrs.merge(key:))
        record.password = password
        record.scope.assign(*scopes)
        record
      end
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

    def public_json(device = nil, **opts)
      json = {
        id: key,
        name:,
        nickname:,
        email: login_email&.address,
        identicon_id:,
        identifier:,
        identifier_type:,
        avatar: avatar_url,
        login_email: login_email&.address,
        password: password_digest&.present?,
        password_changeable: password_changeable?,
        password_changed_at:,
        password_changeable_at:,
        second_factor: second_factor?,
        valid_second_factors:,
        enabled_second_factor_at:,
        saved_backup_codes_at:,
        created_at:,
        updated_at:,
        last_login_at:,
      }

      unless opts[:simple]
        json.merge!(
          scopes: scopes,
          login_emails: login_emails.map { |email| email.public_json(device) },
          remaining_backup_codes: backup_codes&.length || 0,
          single_sign_ons: single_sign_ons.map { |sso| sso.public_json },
          hardware_keys: hardware_keys.map { |key| key.public_json },
          phones: phones.map { |phone| phone.public_json },
          otp_secrets: otp_secrets.map { |otp| otp.public_json },
        )
      end

      json
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
      unless password_changed_at && Masks.conf.password_change_cooldown
        return true
      end

      password_changeable_at < Time.now.utc
    rescue => e
      true
    end

    def password_changeable_at
      cooldown = Masks.conf.password_change_cooldown

      return unless cooldown && password_changed_at

      Masks.time.expires_at(cooldown, after: password_changed_at)
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

    def login_email=(address)
      emails.build(address:).for_login if address&.presence
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

    def valid_second_factors
      second_factors.any? && saved_backup_codes_at
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
      if nickname && format = Masks.conf.nickname_format
        Regexp.new(format)
      end
    end

    def manager=(v)
      @manager = v

      if v
        scope.assign(Masks::Scopes::MANAGE)
      else
        scope.remove(Masks::Scopes::MANAGE)
      end
    end

    private

    def generate_defaults
      self.uuid ||= SecureRandom.uuid
      self.webauthn_id ||= WebAuthn.generate_user_id

      scope.assign(Masks.conf.actor_scopes)
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
        min_chars: Masks.conf.nickname_min_chars,
        max_chars: Masks.conf.nickname_max_chars,
      )
    end

    def validates_password
      if password_challenge && !authenticate(password_challenge)
        return errors.add(:password_challenge, :invalid)
      end

      self.password = self.new_password if new_password && password_challenge

      return unless password

      validates_length(
        password,
        key: :password,
        min_chars: Masks.conf.password_min_chars,
        max_chars: Masks.conf.password_max_chars,
      )

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
      return unless backup_codes && @new_backup_codes

      unless backup_codes.length == Masks.conf.backup_code_limit
        errors.add(:backup_codes, :length, total: Masks.conf.backup_code_limit)
      end

      backup_codes.each do |code|
        validates_length(
          code,
          key: :backup_codes,
          min_chars: Masks.conf.backup_code_min_chars,
          max_chars: Masks.conf.backup_code_max_chars,
        )
      end
    end

    def email_type
      "email"
    end

    def nickname_type
      "nickname"
    end
  end
end
