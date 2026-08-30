class Token < ApplicationRecord
  include TenantScoped

  belongs_to :actor, optional: true
  belongs_to :client, optional: true
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
  end

  def consume!
    update!(consumed_at: Time.current)
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
