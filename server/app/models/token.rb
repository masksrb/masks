class Token < ApplicationRecord
  include TenantScoped

  KINDS = {
    "access" => "AccessToken",
    "refresh" => "RefreshToken",
    "code" => "AuthorizationCode",
    "device" => "DeviceGrant",
    "invitation" => "Invitation",
    "provisioning" => "ProvisioningToken",
    "handshake" => "PendingHandshake",
    "email_verification" => "EmailVerification",
    "password_reset" => "PasswordReset",
    "confirmation" => "ConfirmationCode",
    "initial_access" => "InitialAccessToken",
    "request" => "PendingRequest",
    "login" => "PendingLogin",
    "pushed" => "PushedRequest"
  }.freeze

  self.inheritance_column = "kind"

  belongs_to :actor, optional: true
  belongs_to :client, optional: true
  belongs_to :device, optional: true
  belongs_to :session, optional: true
  belongs_to :parent, class_name: "Token", optional: true

  has_many :children, class_name: "Token", foreign_key: :parent_id, dependent: :nullify

  scope :live, -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }

  attr_reader :secret

  class << self
    def sti_name
      KINDS.key(name.demodulize) || raise(ArgumentError, "#{name} has no token kind")
    end

    def find_sti_class(kind)
      class_name = KINDS.fetch(kind) { raise ActiveRecord::SubclassNotFound, "no token kind called #{kind}" }

      module_parent.const_get(class_name, false)
    end

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
    transaction do
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
  end

  def subject(issuer)
    actor ? issuer.subject_for(actor, client) : root.client&.client_id
  end

  def root
    held = self
    held = held.parent while held.parent

    held
  end

  def lineage
    held = []
    frontier = [ self ]

    while (token = frontier.shift)
      held << token
      frontier.concat(token.children.to_a)
    end

    held
  end

  def revoke_family!
    transaction do
      revoked = 0

      root.lineage.each do |token|
        revoked += 1 if token.live?
        token.update!(consumed_at: Time.current) unless token.consumed?
      end

      revoked
    end
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

  def held(key)
    (payload || {})[key]
  end

  def bound?
    jkt.present?
  end

  def confirmation
    { "jkt" => jkt } if bound?
  end

  def bound_to?(proof)
    proof.present? && ActiveSupport::SecurityUtils.secure_compare(jkt.to_s, proof.jkt.to_s)
  end
end
