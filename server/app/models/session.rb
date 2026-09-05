class Session < ApplicationRecord
  include TenantScoped

  LIFETIME = 14.days

  belongs_to :actor

  scope :live, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  attr_reader :secret

  class << self
    def start!(actor:, user_agent: nil, ip_address: nil, amr: [])
      secret = SecureRandom.urlsafe_base64(48)

      session = create!(
        actor: actor,
        digest: Digest::SHA256.hexdigest(secret),
        user_agent: user_agent,
        ip_address: ip_address,
        authenticated_at: Time.current,
        amr: Array(amr),
        expires_at: LIFETIME.from_now
      )

      session.instance_variable_set(:@secret, secret)
      session
    end

    def resume(secret)
      return nil if secret.blank?

      live.find_by(digest: Digest::SHA256.hexdigest(secret.to_s))
    end
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
