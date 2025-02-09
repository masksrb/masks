module Masks
  module SettingsColumn
    extend ActiveSupport::Concern

    included do
      include SettingsAttribute

      serialize :settings, coder: JSON

      after_initialize :generate_settings
    end

    private

    def generate_settings
      self.settings ||= {}
    end
  end
end
