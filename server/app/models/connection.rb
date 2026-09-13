class Connection < ApplicationRecord
  include TenantScoped

  belongs_to :provider
  belongs_to :actor

  validates :subject, presence: true,
                      uniqueness: { scope: [ :tenant_id, :provider_id ] }

  scope :live, -> { where(revoked_at: nil) }

  class << self
    def record!(provider:, actor:, identity:)
      subject = identity[provider.subject_claim].presence ||
        identity["sub"].presence ||
        raise(ArgumentError, "#{provider.name} returned no #{provider.subject_claim} to identify the account by")

      connection = find_or_initialize_by(provider: provider, subject: subject.to_s)

      connection.actor = actor
      connection.label = identity[provider.label_claim].presence || connection.label
      connection.connected_at = Time.current
      connection.revoked_at = nil
      connection.revoked_reason = nil
      connection.absorb_identity(identity)
      connection.save!

      connection
    end
  end

  def absorb_identity(identity)
    held = identity["email"].to_s.strip.downcase.presence

    return self if held.nil?

    self.email = held
    self.email_verified = identity["email_verified"] == true

    self
  end

  def signed_in!
    update!(signed_in_at: Time.current)

    self
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!(reason: "revoked")
    update!(revoked_at: Time.current, revoked_reason: reason)

    self
  end
end
