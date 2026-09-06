class Connection < ApplicationRecord
  class Revoked < StandardError; end

  include TenantScoped

  SKEW = 60.seconds
  DEFAULT_LIFETIME = 55.minutes

  encrypts :refresh_token
  encrypts :access_token

  belongs_to :provider
  belongs_to :actor

  validates :subject, presence: true,
                      uniqueness: { scope: [ :tenant_id, :provider_id ] }

  scope :live, -> { where(revoked_at: nil) }

  class << self
    def record!(provider:, actor:, tokens:, identity:)
      subject = identity[provider.subject_claim].presence ||
        tokens["sub"].presence ||
        raise(ArgumentError, "#{provider.name} returned no #{provider.subject_claim} to identify the account by")

      connection = find_or_initialize_by(provider: provider, subject: subject.to_s)

      connection.actor = actor
      connection.label = identity[provider.label_claim].presence || connection.label
      connection.scopes = Scopes.join(tokens["scope"].presence || provider.scope_list)
      connection.connected_at = Time.current
      connection.revoked_at = nil
      connection.revoked_reason = nil
      connection.absorb(tokens)
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

  def scope_list
    Scopes.list(scopes)
  end

  def to_h
    {
      "id" => uuid,
      "provider" => provider.key,
      "label" => label,
      "subject" => subject,
      "scope" => Scopes.join(scope_list),
      "connected_at" => connected_at&.iso8601
    }
  end

  def release!
    raise Revoked, revoked_reason.presence || "that connection has been revoked" if revoked?

    refresh! if stale?
    access_token
  end

  def stale?
    access_token.blank? ||
      access_token_expires_at.nil? ||
      access_token_expires_at <= SKEW.from_now
  end

  def refresh!
    raise Revoked, "that connection holds no refresh token" if refresh_token.blank?

    absorb(provider.refresh!(refresh_token))
    save!
    self
  rescue Provider::Refused => e
    revoke!(reason: e.message, upstream: false)
    raise Revoked, "#{provider.name} refused the refresh: #{e.message}"
  end

  def revoke!(reason: "revoked", upstream: true)
    provider.revoke!(refresh_token.presence || access_token) if upstream

    update!(
      refresh_token: nil,
      access_token: nil,
      access_token_expires_at: nil,
      revoked_at: Time.current,
      revoked_reason: reason
    )

    self
  end

  def absorb(tokens)
    self.access_token = tokens["access_token"].presence || access_token
    self.refresh_token = tokens["refresh_token"].presence || refresh_token
    self.access_token_expires_at = expiry_from(tokens)

    self
  end

  private

    def expiry_from(tokens)
      seconds = tokens["expires_in"].presence&.to_i

      return DEFAULT_LIFETIME.from_now if seconds.nil? || seconds <= 0

      seconds.seconds.from_now
    end
end
