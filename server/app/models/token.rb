class Token < ApplicationRecord
  include TenantScoped

  belongs_to :actor, optional: true
  belongs_to :client, optional: true
  belongs_to :device, optional: true
  belongs_to :session, optional: true
  belongs_to :parent, class_name: "Token", optional: true

  has_many :children, class_name: "Token", foreign_key: :parent_id, dependent: :nullify

  scope :live, -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }

  attr_reader :secret

  class << self
    def lifetime
      10.minutes
    end

    def mint!(**attributes)
      secret = SecureRandom.urlsafe_base64(48)
      attributes[:device] ||= attributes[:parent]&.device
      attributes[:session] ||= attributes[:parent]&.session

      token = create!(
        **attributes,
        digest: Digest::SHA256.hexdigest(secret),
        expires_at: attributes[:expires_at] || lifetime.from_now
      )

      token.instance_variable_set(:@secret, secret)
      token
    end

    def redeem(secret)
      return nil if secret.blank?

      live.find_by(digest: Digest::SHA256.hexdigest(secret.to_s))
    end

    def spent(secret)
      return nil if secret.blank?

      find_by(digest: Digest::SHA256.hexdigest(secret.to_s))
    end

    def claim(secret)
      return nil if secret.blank?

      digest = Digest::SHA256.hexdigest(secret.to_s)
      now = Time.current
      taken = live.where(digest: digest).update_all(consumed_at: now, updated_at: now)

      taken.zero? ? nil : find_by(digest: digest)
    end
  end

  def consume!
    update!(consumed_at: Time.current)
  end

  def revoke!
    revoked = 0
    frontier = [ self ]

    while (token = frontier.shift)
      next if token.consumed?

      token.update!(consumed_at: Time.current)
      revoked += 1
      frontier.concat(token.children.to_a)
    end

    revoked
  end

  def root
    held = self
    held = held.parent while held.parent

    held
  end

  def revoke_family!
    revoked = 0
    frontier = [ root ]

    while (token = frontier.shift)
      revoked += 1 if token.live?
      token.update!(consumed_at: Time.current) unless token.consumed?
      frontier.concat(token.children.to_a)
    end

    revoked
  end

  def consumed?
    consumed_at.present?
  end

  def live?
    !consumed? && expires_at > Time.current
  end

  def expires_in
    [ (expires_at - Time.current).to_i, 0 ].max
  end

  def scope_list
    Scopes.list(scopes)
  end
end
