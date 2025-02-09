module Masks
  class Installation < ApplicationRecord
    self.table_name = "masks_installations"

    include SettingsColumn

    encrypts :settings

    has_one_attached :light_logo
    has_one_attached :dark_logo
    has_one_attached :favicon

    scope :active, -> { where(expired_at: nil) }

    after_create :upload_assets

    def upload_assets
      filename = "app/assets/images/masks.png"

      upload_file(:light_logo, Masks::Engine.root.join(filename))
      upload_file(:dark_logo, Masks::Engine.root.join(filename))
      upload_file(:favicon, Masks::Engine.root.join(filename))
    end

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

#       # validates :name,
#       #           :client_types,
#       #           :client_types,
#       #           :backup_codes,
#       #           :passwords,
#       #           :theme,
#       #           :prompts,
#       #           presence: true
#       # validates :url, presence: true, url: true
#       # validates :timezone,
#       #           presence: true,
#       #           inclusion: {
#       #             in: ActiveSupport::TimeZone.all.map { |tz| tz.tzinfo.name },
#       #           }

#       def prompts
#         setting(:prompts, default: [
#           'Masks::Prompts::Device',
#           'Masks::Prompts::SingleSignOn',
#           'Masks::Prompts::Identifier',
#           'Masks::Prompts::LoginLink',
#           'Masks::Prompts::Password',
#           'Masks::Prompts::FirstFactor',
#           'Masks::Prompts::Phone',
#           'Masks::Prompts::Webauthn',
#           'Masks::Prompts::OneTimePassword',
#           'Masks::Prompts::BackupCode',
#           'Masks::Prompts::SecondFactor',
#           'Masks::Prompts::Email',
#           'Masks::Prompts::ResetPassword',
#           'Masks::Prompts::OAuth',
#           'Masks::Prompts::Profile',
#           'Masks::Prompts::LastLogin',
#           'Masks::Prompts::Internal',
#         ]).map(&:constantize)
#       end

#       def provider_types
#         @provider_types ||=
#           setting(:providers, :types, default: {})
#             .map { |key, value| [key, value.constantize] }
#             .to_h
#       end

#       def favicon_url
#         return rails_storage_proxy_url(favicon) if favicon.attached?

#         super
#       end

#       def light_logo_url
#         return rails_storage_proxy_url(light_logo) if light_logo.attached?

#         super
#       end

#       def dark_logo_url
#         return rails_storage_proxy_url(dark_logo) if dark_logo.attached?

#         super
#       end

#       def writable?
#         true
#       end

#       def modify(updates)
#         return unless updates

#         updates = updates.deep_stringify_keys
#         reconfigured =
#           RECONFIGURATION_KEYS.any? do |key|
#             exists = updates.dig(*key.slice(0...-1))&.key?(key.last)

#             next unless exists

#             current = setting(*key)
#             updated = updates.dig(*key)
#             current != updated
#           end

#         super updates

#         self.reconfigured_at = Time.current if reconfigured

#         save!
#       end

#       def needs_restart
#         !!reconfigured_at&.present?
#       end

#       private

#     end
#   end
# end
