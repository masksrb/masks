module Masks
  module Server
    class Consent < ApplicationRecord
      include TenantScoped

      LONGEST = 400.days

      belongs_to :actor
      belongs_to :client

      scope :live, -> { where(revoked_at: nil).where("consents.expires_at IS NULL OR consents.expires_at > ?", Time.current) }

      class << self
        def record!(actor:, client:, scopes:, audience:, details: nil)
          consent = find_or_initialize_by(actor: actor, client: client)
          consent.assign_attributes(scopes: "", audience: [], authorization_details: []) unless consent.new_record? || consent.live?
          consent.revoked_at = nil
          consent.scopes = Scopes.join(Scopes.list(consent.scopes) | Scopes.list(scopes))
          consent.audience = (consent.audience | Array(audience)).compact
          consent.remember(details)
          consent.expires_at = client.consent_lifetime&.seconds&.from_now
          consent.save!
          consent
        end

        def covers?(actor:, client:, scopes:, audience:, details: nil)
          consent = live.find_by(actor: actor, client: client)
          return false if consent.nil?

          Scopes.covers?(consent.scopes, scopes) &&
            (Array(audience) - consent.audience).empty? &&
            (details.nil? || details.covered_by?(consent.remembered))
        end
      end

      def live?
        revoked_at.nil? && (expires_at.nil? || expires_at.future?)
      end

      def held_details
        authorization_details.select { |held| Time.zone.parse(held["expires_at"].to_s)&.future? }
      end

      def remembered
        held_details.map { |held| held["entry"] }
      end

      def remember(details)
        kept = held_details
        return self.authorization_details = kept if details.nil?

        declared = AuthorizationDetails.declared

        details.entries.each do |entry|
          lasts = declared.dig(entry["type"], "remember")
          next unless lasts.is_a?(Integer) && lasts.positive?

          kept.reject! { |held| held["entry"] == entry }
          kept << { "entry" => entry, "expires_at" => [ lasts.seconds, LONGEST ].min.from_now.utc.iso8601 }
        end

        self.authorization_details = kept
      end

      def revoke!
        update!(revoked_at: Time.current)
      end
    end
  end
end
