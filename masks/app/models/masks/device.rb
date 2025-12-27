# frozen_string_literal: true

module Masks
  class Device < ApplicationRecord
    self.table_name = "masks_devices"

    class << self
      def identify(id, request: nil)
        create_with(request:).find_or_initialize_by(public_id: id)
      end
    end

    attribute :request

    validates :public_id, presence: true, uniqueness: true
    validates :known?, :user_agent, presence: true
    validates :ip_address, ip: true

    delegate :name,
             :device_type,
             :device_name,
             :os_name,
             :known?,
             to: :detected,
             allow_nil: true

    after_initialize :generate_defaults

    serialize :captcha, coder: JSON

    def verify_captcha(name, data)
      self.captcha ||= {}
      self.captcha[name.to_s] = data
    end

    def passed_captcha?
      false
    end

    def session_key
      "#{public_id}:#{version}"
    end

    def rotate
      self.version += 1
    end

    def logout!
      transaction do
        rotate
        tokens.usable.find_each(&:revoke!)
        save!
      end
    end

    def block
      self.blocked_at = Time.now.utc
    end

    def unblock
      self.blocked_at = nil
    end

    def block!
      block
      save!
    end

    def blocked?
      blocked_at && Masks.time.expired?(blocked_at)
    end

    def valid_request?(request)
      validate

      errors.add(:user_agent, :mismatch) if request.user_agent != user_agent
      errors.add(:ip_address, :mismatch) if request.remote_ip != ip_address
      errors.none?
    end

    def public_json
      { id: public_id }
    end

    private

    def detected
      @detected ||= Masks.cls(:device_detector).new(user_agent) if user_agent
    end

    def generate_defaults
      self.version ||= 0
      self.ip_address ||= request&.remote_ip
      self.user_agent ||= request&.user_agent
      self.session_id ||= request&.session&.try(:id)
    end
  end
end
