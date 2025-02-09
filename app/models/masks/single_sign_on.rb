module Masks
  class SingleSignOn < ApplicationRecord
    self.table_name = "masks_single_sign_ons"

    include Masks::Settings

    serialize :settings, coder: JSON
    encrypts :settings

    validates :key, :settings, presence: true
    validates :key, uniqueness: { scope: %i[provider_id] }

    belongs_to :provider
    belongs_to :actor, class_name: Masks.conf.actor_model

    before_validation :generate_key

    def public_json
      {
        id: key,
        created_at:,
        identifier:,
        deletable: deletable?,
        provider: provider.public_json,
      }
    end

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
