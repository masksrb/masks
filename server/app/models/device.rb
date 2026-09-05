class Device < ApplicationRecord
  include TenantScoped

  COOKIE = "masks_device".freeze
  LIFETIME = 400.days
  IDLE = 5.minutes
  UNKNOWN = "Unknown device".freeze

  has_many :sessions, dependent: :nullify
  has_many :tokens, dependent: :nullify
  has_many :device_factors, dependent: :destroy

  validates :public_id, presence: true, uniqueness: { scope: :tenant_id }

  scope :newest_first, -> { order(last_seen_at: :desc) }
  scope :allowed, -> { where(blocked_at: nil) }

  after_initialize :generate_defaults, if: :new_record?

  class << self
    def identify(public_id, user_agent: nil, ip_address: nil)
      device = find_or_initialize_by(public_id: public_id.presence || mint)

      device.seen!(user_agent: user_agent, ip_address: ip_address)
    end

    def mint
      SecureRandom.urlsafe_base64(24)
    end

    def version
      SecureRandom.hex(16)
    end

    def for_actor(actor)
      where(id: Session.where(actor: actor).select(:device_id))
    end
  end

  def seen!(user_agent: nil, ip_address: nil)
    self.user_agent = user_agent if user_agent.present?
    self.ip_address = ip_address if ip_address.present?
    self.last_seen_at = Time.current if new_record? || last_seen_at < IDLE.ago

    save! if new_record? || changed?
    self
  end

  def label
    name.presence || detected_label
  end

  def category
    detected.device_type.presence || "unknown"
  end

  def known?
    user_agent.present? && detected.known?
  end

  def blocked?
    blocked_at.present?
  end

  def block!
    transaction do
      update!(blocked_at: Time.current)
      sign_out!
    end
  end

  def unblock!
    update!(blocked_at: nil)
  end

  def rotate!
    update!(version: self.class.version)
  end

  def sign_out!
    transaction do
      rotate!
      sessions.live.find_each(&:revoke!)
      tokens.live.find_each(&:revoke!)
      device_factors.delete_all
    end

    self
  end

  def carries?(session)
    !blocked? && session.device_version == version
  end

  def remembers?(actor, factor)
    DeviceFactor.satisfied?(device: self, actor: actor, factor: factor)
  end

  private

    def detected
      @detected ||= DeviceDetector.new(user_agent.to_s)
    end

    def detected_label
      named = [ detected.name, detected.os_name ].map(&:presence).compact

      named.any? ? named.join(" on ") : UNKNOWN
    end

    def generate_defaults
      self.public_id ||= self.class.mint
      self.version ||= self.class.version
      self.last_seen_at ||= Time.current
    end
end
