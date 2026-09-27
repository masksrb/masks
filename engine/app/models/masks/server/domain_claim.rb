module Masks
  module Server
    class DomainClaim < ApplicationRecord
      class Taken < StandardError; end

      include TenantScoped

      PREFIX = "_masks-challenge".freeze
      VALUE = "masks-verification=".freeze
      GRACE = 7.days
      TIMEOUT = 5
      HOSTNAME = /\A(?=.{4,253}\z)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/

      belongs_to :provider, optional: true

      scope :verified, -> { where.not(verified_at: nil) }

      normalizes :domain, with: ->(value) { value.to_s.strip.downcase.delete_prefix("@").delete_suffix(".") }

      validates :domain, format: { with: HOSTNAME, message: "is not a domain name" },
                         uniqueness: { scope: :tenant_id }
      validate :provider_signs_in

      before_validation(on: :create) { self.token ||= SecureRandom.hex(20) }

      class << self
        def for_email(email)
          domain = email.to_s.strip.downcase.split("@", 2).last

          return nil if domain.blank? || !email.to_s.include?("@")

          verified.includes(:provider).find_by(domain: domain)
        end

        def txt_records(name)
          Resolv::DNS.open do |dns|
            dns.timeouts = TIMEOUT
            dns.getresources(name, Resolv::DNS::Resource::IN::TXT).flat_map(&:strings)
          end
        rescue Resolv::ResolvError, SocketError, Timeout::Error
          []
        end
      end

      def record_name
        "#{PREFIX}.#{domain}"
      end

      def record_value
        "#{VALUE}#{token}"
      end

      def verified?
        verified_at.present?
      end

      def check!(now: Time.current)
        found = self.class.txt_records(record_name).any? { |value| ActiveSupport::SecurityUtils.secure_compare(value.strip, record_value) }

        if found
          assign_attributes(verified_at: verified_at || now, missing_since: nil)
        elsif verified?
          self.missing_since ||= now
          assign_attributes(verified_at: nil, missing_since: nil) if missing_since <= now - GRACE
        end

        self.checked_at = now
        save!
        found
      rescue ActiveRecord::RecordNotUnique
        raise Taken, "#{domain} is already proven by another tenant"
      end

      def discovers
        provider if verified? && provider&.signs_in? && provider.archived_at.nil?
      end

      private

        def provider_signs_in
          errors.add(:provider, "cannot sign anybody in") if provider && !provider.signs_in?
        end
    end
  end
end
