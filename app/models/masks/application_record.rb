module Masks
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true

    scope :latest, -> { order(created_at: :desc) }

    class << self
      def generate_key(from:)
        before_validation unless: :key, on: :create do
          generate_key_from(try(from))
        end
      end
    end

    def rails_storage_proxy_url(variant)
      Rails.application.routes.url_helpers.rails_storage_proxy_url(
        variant,
        **Masks.default_url_options,
      )
    end

    def generate_key_from(name)
      return unless name&.present?

      key = name.parameterize

      loop do
        break if self.class.where(key:).none?

        key = "#{name.parameterize}-#{SecureRandom.hex([*1..4].sample)}"
      end

      self.key = key
    end
  end
end
