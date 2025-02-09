module Masks
  module ActorSettings
    extend ActiveSupport::Concern

    included do
      include Masks::Settings
      include Masks::Seedable

      setting :key, :string
      setting :name, :string
      setting :uuid, :string
      setting :nickname, :string
      setting :scopes, [:string]
      setting :avatar_url, :string
      setting :tz, :string, default: -> { Masks.conf.tz }

      timestamps(:onboarded_at, :password_changed_at)

      delegate :masks_manager?, to: :scope
    end

    def session_key
      key
    end

    def scope
      @scope ||= Masks::Scopes.new(self, :scopes)
    end
  end
end
