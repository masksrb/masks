# frozen_string_literal: true

module Masks
  class Device < ApplicationRecord
    self.table_name = "masks_devices"

    include Cleanable

    cleanup :updated_at do
      Masks.conf.duration(:device_inactive)
    end

    class << self
      def load(session, id)
        create_with(session:).find_or_initialize_by(public_id: id)
      end

      def cookie_key
        Masks.conf.device_cookie_name
      end

      def cookie_expiry
        Masks.time.expires_at(:device_cookie_lifetime)
      end
    end

    attribute :request
    attribute :session

    has_many :tokens, class_name: "Masks::Token"
    has_many :actors,
             -> { distinct },
             class_name: Masks.conf.actor_model,
             through: :tokens

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
      @detected ||= DeviceDetector.new(user_agent) if user_agent
    end

    def generate_defaults
      self.version ||= 0
      self.ip_address ||= session&.rails_request&.remote_ip
      self.user_agent ||= session&.rails_request&.user_agent
      self.session_id ||= session&.rails_session&.try(:id)
    end
  end
end
