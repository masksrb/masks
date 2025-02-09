module Masks
  module Installations
    class Database < Masks::ApplicationRecord
      include Masks::Installer
      include SettingsColumn

      RECONFIGURATION_KEYS = [
        %w[monitoring sentry dsn],
        %w[monitoring newrelic license_key],
        %w[monitoring newrelic app],
        %w[sessions timeout],
        %w[sessions lifetime],
        %w[devices timeout],
        %w[devices cookie],
        %w[devices class],
      ]

      class << self
        def current
          active.first!
        rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid
          new(settings: Masks.env)
        end
      end

      self.table_name = "masks_installations"

      encrypts :settings

      has_one_attached :light_logo
      has_one_attached :dark_logo
      has_one_attached :favicon

      scope :active, -> { where(expired_at: nil) }

      validates :name,
                :client_types,
                :client_types,
                :backup_codes,
                :passwords,
                :theme,
                :prompts,
                presence: true
      validates :url, presence: true, url: true
      validates :timezone,
                presence: true,
                inclusion: {
                  in: ActiveSupport::TimeZone.all.map { |tz| tz.tzinfo.name },
                }

      def light_logo_file=(path)
        upload_file(:light_logo, path)
      end

      def dark_logo_file=(path)
        upload_file(:dark_logo, path)
      end

      def favicon_file=(path)
        upload_file(:favicon, path)
      end

      def favicon_url
        return rails_storage_proxy_url(favicon) if favicon.attached?

        super
      end

      def light_logo_url
        return rails_storage_proxy_url(light_logo) if light_logo.attached?

        super
      end

      def dark_logo_url
        return rails_storage_proxy_url(dark_logo) if dark_logo.attached?

        super
      end

      def writable?
        true
      end

      def modify(updates)
        return unless updates

        updates = updates.deep_stringify_keys
        reconfigured =
          RECONFIGURATION_KEYS.any? do |key|
            exists = updates.dig(*key.slice(0...-1))&.key?(key.last)

            next unless exists

            current = setting(*key)
            updated = updates.dig(*key)
            current != updated
          end

        merge_settings(updates)

        self.reconfigured_at = Time.current if reconfigured

        save!
      end

      def needs_restart
        !!reconfigured_at&.present?
      end

      private

      def upload_file(key, path)
        case path
        when Pathname
          io = File.open(path)
          filename = path.basename.to_s
        else
          raise "unsupported"
        end

        send(key).attach(io:, filename:)
      end
    end
  end
end
