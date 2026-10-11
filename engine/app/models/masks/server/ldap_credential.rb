module Masks
  module Server
    class LdapCredential < Token
      LABEL = /\A[a-z0-9][a-z0-9._-]{0,62}\z/
      LIFETIME = 100.years

      class Refused < StandardError; end

      class << self
        def issue!(label:, by:)
          name = label.to_s.strip.downcase
          raise Refused, "a label is lowercase letters, digits, dots, dashes, and underscores" unless name.match?(LABEL)
          raise Refused, "a live LDAP credential is already labeled #{name}" if named(name)

          mint!(payload: { "label" => name, "issued_by" => by&.uuid }.compact, expires_at: LIFETIME.from_now)
        end

        def named(label)
          live.find_by("payload->>'label' = ?", label.to_s.downcase)
        end

        def check(label, secret)
          held = named(label)
          offered = Digest::SHA256.hexdigest(secret.to_s)

          return nil unless held && secret.present? && ActiveSupport::SecurityUtils.secure_compare(held.digest, offered)

          held
        end
      end

      def label
        held("label")
      end

      def issued_by
        Actor.find_by(uuid: held("issued_by")) if held("issued_by")
      end

      def used_at
        held("used_at")&.then { |value| Time.zone.parse(value) }
      end

      def used!
        return if used_at && used_at > 5.minutes.ago

        update_columns(payload: (payload || {}).merge("used_at" => Time.current.iso8601))
      end
    end
  end
end
