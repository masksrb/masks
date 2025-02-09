module Masks
  class SingleSignOn < ApplicationRecord
    self.table_name = "masks_single_sign_ons"

    include SettingsColumn

    encrypts :settings

    validates :key, :settings, presence: true
    validates :key, uniqueness: { scope: %i[provider_id] }

    belongs_to :provider
    belongs_to :actor

    before_validation :generate_key

    def identifier
      provider.identifier(settings)
    end

    def avatar
      provider.avatar(settings)
    end

    def deletable?
      actor.password || actor.login_emails.any?
    end

    def permanently_delete
      destroy if deletable?
    end

    private

    def generate_key
      self.key = settings&.dig("uid")
    end
  end
end
