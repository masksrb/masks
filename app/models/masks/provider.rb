# frozen_string_literal: true

module Masks
  class Provider < ApplicationRecord
    include SettingsColumn
    include Seedable

    self.table_name = "masks_providers"
    self.inheritance_column = nil

    class << self
      def seed(key:, **attrs)
        key = key.to_s

        return if where(key:).any?

        attrs = { type: key, key: }.merge(attrs.symbolize_keys)

        new(attrs)
      end
    end

    validates :name, :type, presence: true
    validates :key, presence: true, uniqueness: true

    has_many :single_sign_ons, class_name: "Masks::SingleSignOn"
    has_many :client_providers,
             class_name: "Masks::ClientProvider",
             autosave: true

    scope :common, -> { where(disabled_at: nil, common: true) }
    scope :enabled, -> { where(disabled_at: nil) }

    after_initialize :generate_defaults

    generate_key from: :name

    writable(
      key: :string,
      name: :string,
      type: :string,
      common: :boolean,
      enabled: :boolean,
      clients: [:string],
    )

    timestamps(:disabled_at)

    def usable?
      enabled? && setup?
    end

    def enabled=(value)
      Masks.to_bool(value) ? enable : disable
    end

    def enabled
      !self.disabled_at
    end

    def disable
      self.disabled_at = Time.current
    end

    def enable
      self.disabled_at = nil
    end

    def session_key
      key
    end

    def to_param
      key
    end

    def omniauth
      @omniauth ||= Masks.installation.provider_types.fetch(type.to_s).new(self)
    rescue KeyError => e
      @omniauth ||= type.constantize.new(self)
    rescue StandardError
      @omniauth = Masks::Providers::NotFound.new(self)
    end

    def public_settings
      self.class.all_settings.merge(omniauth.class.all_settings)
    end

    def method_missing(method, *args, **opts, &block)
      if omniauth.class.settings[
           method.to_s.delete_suffix("=").delete_suffix("?")
         ]
        omniauth.send(method, *args, **opts, &block)
      else
        super
      end
    end

    def assign_client=(v)
      client_providers.find_or_initialize_by(client: Masks.client(v))
    end

    def remove_client=(v)
      client = Masks.client(v)
      client_providers.each do |record|
        record.mark_for_destruction if record.client_id == client.id
      end
    end

    delegate :setup?,
             :omniauth_strategy,
             :omniauth_args,
             :omniauth_opts,
             to: :omniauth

    def public_type
      type
    end

    def identifier(auth_hash)
      auth_hash.dig("info", "name") || auth_hash.dig("info", "nickname") ||
        auth_hash.dig("info", "email")
    end

    def avatar(auth_hash)
      auth_hash.dig("info", "image")
    end

    private

    def generate_defaults
      name = self.class.name.split("::").last

      self.name ||=
        I18n.t("sso.#{name.underscore}.name", default: name.humanize)
    end
  end
end
