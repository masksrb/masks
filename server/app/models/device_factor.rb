class DeviceFactor < ApplicationRecord
  include TenantScoped

  SECOND_FACTOR = "second_factor".freeze
  LIFETIME = 30.days

  belongs_to :device
  belongs_to :actor

  scope :live, -> { where("expires_at > ?", Time.current) }

  class << self
    def remember!(device:, actor:, factor: SECOND_FACTOR, expiry: LIFETIME)
      return nil if device.nil? || actor.nil?

      record = find_or_initialize_by(device: device, actor: actor, factor: factor.to_s)
      record.update!(satisfied_at: Time.current, expires_at: expiry.from_now)
      record
    end

    def satisfied?(device:, actor:, factor: SECOND_FACTOR)
      return false if device.nil? || actor.nil?

      live.exists?(device: device, actor: actor, factor: factor.to_s)
    end

    def forget!(actor:, factor: SECOND_FACTOR)
      where(actor: actor, factor: factor.to_s).delete_all
    end
  end

  def expired?
    expires_at <= Time.current
  end
end
