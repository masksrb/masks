class Consent < ApplicationRecord
  include TenantScoped

  belongs_to :actor
  belongs_to :client

  scope :live, -> { where(revoked_at: nil) }

  class << self
    def record!(actor:, client:, scopes:, audience:)
      consent = live.find_or_initialize_by(actor: actor, client: client)
      consent.scopes = Scopes.join(Scopes.list(consent.scopes) | Scopes.list(scopes))
      consent.audience = (consent.audience | Array(audience)).compact
      consent.revoked_at = nil
      consent.save!
      consent
    end

    def covers?(actor:, client:, scopes:, audience:)
      consent = live.find_by(actor: actor, client: client)
      return false if consent.nil?

      Scopes.covers?(consent.scopes, scopes) &&
        (Array(audience) - consent.audience).empty?
    end
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
