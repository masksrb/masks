module Masks
  class Phone < ApplicationRecord
    self.table_name = "masks_phones"

    validates :number, phone: true, uniqueness: true
    validate :validate_adapter

    belongs_to :actor

    def send_code
      return unless valid?

      adapter.notify(self)
    rescue => e
      false
    end

    def verify
      self.verified_at = Time.now.utc
    end

    def verify_code(code)
      return unless valid?

      if adapter.verify(self, code)
        self.verified_at = Time.now.utc
        save
      end
    end

    def number=(value)
      number = Phonelib.parse(value)

      super number.e164 if number.valid?
    end

    private

    def validate_adapter
      errors.add(:adapter, :misconfigured) unless adapter&.setup?
    end

    def adapter
      @adapter ||= Masks.installation.adapter
    end
  end
end
