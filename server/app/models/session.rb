class Session < ApplicationRecord
  include TenantScoped

  LIFETIME = 14.days

  belongs_to :actor
  belongs_to :device, optional: true

  scope :live, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  attr_reader :secret

  class << self
    def start!(actor:, device: nil, user_agent: nil, ip_address: nil, amr: [], origin: nil)
      secret = SecureRandom.urlsafe_base64(48)

      session = create!(
        actor: actor,
        device: device,
        device_version: device&.version,
        digest: Digest::SHA256.hexdigest(secret),
        user_agent: user_agent,
        ip_address: ip_address,
        origin: origin.presence || Current.origin,
        authenticated_at: Time.current,
        amr: Array(amr),
        expires_at: LIFETIME.from_now
      )

      session.instance_variable_set(:@secret, secret)
      session
    end

    def resume(secret)
      return nil if secret.blank?

      session = live.includes(:device).find_by(digest: Digest::SHA256.hexdigest(secret.to_s))

      session if session&.bound?
    end
  end

  def bound?
    device.nil? || device.carries?(self)
  end

  def relying_parties
    Client
      .where(id: Token.where(session_id: id).select(:client_id))
      .where.not(backchannel_logout_uri: [ nil, "" ])
      .distinct
  end

  def revoke!
    return true if revoked_at.present?

    update!(revoked_at: Time.current)
    BackchannelLogout.announce(self)

    true
  end
end
