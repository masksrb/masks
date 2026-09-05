class Actor < ApplicationRecord
  include TenantScoped

  has_secure_password validations: false

  encrypts :otp_secret

  has_many :tokens, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :consents, dependent: :destroy
  has_many :device_factors, dependent: :destroy

  validates :nickname, presence: true,
                       uniqueness: { scope: :tenant_id, case_sensitive: false },
                       format: { with: /\A[a-z0-9][a-z0-9._-]*\z/i }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  before_save :activate_once_a_password_exists

  normalizes :nickname, with: ->(value) { value.to_s.strip }
  normalizes :email, with: ->(value) { value.to_s.strip.downcase.presence }

  normalizes :name, :given_name, :family_name, :middle_name, :profile_url, :picture_url,
             :website_url, :gender, :birthdate, :zoneinfo, :locale,
             with: ->(value) { value.to_s.strip.presence }

  class << self
    def locate(identifier)
      find_by(nickname: identifier.to_s.strip) ||
        find_by(email: identifier.to_s.strip.downcase)
    end

    def authenticate(identifier, password)
      actor = locate(identifier)

      return burn(password) if actor.nil? || actor.password_digest.blank? || !actor.activated?

      actor.authenticate(password.to_s) || nil
    end

    def invite!(nickname:, email:, scopes: nil)
      create!(
        nickname: nickname,
        email: email,
        scopes: Scopes.join(Scopes.list(scopes).presence || Scopes::STANDARD)
      )
    end

    def decoy_digest
      @decoy_digest ||= BCrypt::Password.create(SecureRandom.hex(16))
    end

    private

      def burn(password)
        BCrypt::Password.new(decoy_digest) == password.to_s
        nil
      end
  end

  def devices
    Device.for_actor(self)
  end

  def scope_list
    list = Scopes.list(scopes)

    list.empty? ? Scopes::STANDARD.dup : list
  end

  def permitted_scopes(requested)
    wanted = Scopes.list(requested)
    available = scope_list
    available |= connection_scopes if wanted.any? { |scope| Scopes.connection?(scope) }

    Scopes.granted(wanted, available)
  end

  def connection_scopes
    return [] unless persisted?

    Connection.live.where(actor_id: id).includes(:provider)
              .filter_map { |held| held.provider&.release_scope }.uniq
  end

  def holds?(scope)
    scope_list.include?(scope.to_s)
  end

  def withheld(requested)
    Scopes.list(requested) - permitted_scopes(requested)
  end

  def activated?
    activated_at.present?
  end

  def invited?
    !activated?
  end

  def activate!(password, verifying_email: false)
    self.password = password
    self.email_verified_at = Time.current if verifying_email && email.present?
    save!
  end

  def reset_password!(password, verifying_email: false, keeping: nil)
    transaction do
      activate!(password, verifying_email: verifying_email)
      sign_out_everywhere!(keeping: keeping)
    end
  end

  def change_password!(current, password, keeping: nil)
    return false unless activated? && authenticate(current.to_s)

    reset_password!(password, keeping: keeping)
    true
  end

  def sign_out_everywhere!(keeping: nil)
    held = sessions.live
    held = held.where.not(id: keeping.id) if keeping

    held.find_each(&:revoke!)
    RefreshToken.where(actor_id: id).live.find_each(&:revoke!)
    DeviceFactor.forget!(actor: self)
  end

  def otp?
    otp_enabled_at.present? && otp_secret.present?
  end

  def verify_otp(code)
    return false unless otp?

    ROTP::TOTP.new(otp_secret).verify(code.to_s.strip, drift_behind: 30).present?
  end

  BACKUP_CODES = 10
  BACKUP_CODE_BYTES = 8

  def backup_codes?
    backup_code_digests.any?
  end

  def backup_codes_remaining
    backup_code_digests.length
  end

  # Returned once and never recoverable, like every other credential here.
  # High entropy, so a digest rather than bcrypt: there is nothing to brute
  # force in 64 bits of SecureRandom, and a login has to check ten of them.
  def generate_backup_codes!
    codes = Array.new(BACKUP_CODES) { SecureRandom.hex(BACKUP_CODE_BYTES) }

    update!(
      backup_code_digests: codes.map { |code| self.class.digest_backup_code(code) },
      backup_codes_generated_at: Time.current
    )

    codes
  end

  def verify_backup_code(code)
    return false unless backup_codes?

    digest = self.class.digest_backup_code(code)
    remaining = backup_code_digests.reject do |held|
      ActiveSupport::SecurityUtils.secure_compare(held.to_s, digest)
    end

    return false if remaining.length == backup_code_digests.length

    update!(backup_code_digests: remaining)
    true
  end

  def self.digest_backup_code(code)
    Digest::SHA256.hexdigest(code.to_s.strip.downcase.delete("^a-f0-9"))
  end

  PROFILE_CLAIMS = {
    "name" => :name,
    "given_name" => :given_name,
    "family_name" => :family_name,
    "middle_name" => :middle_name,
    "nickname" => :nickname,
    "preferred_username" => :nickname,
    "profile" => :profile_url,
    "picture" => :picture_url,
    "website" => :website_url,
    "gender" => :gender,
    "birthdate" => :birthdate,
    "zoneinfo" => :zoneinfo,
    "locale" => :locale
  }.freeze

  def claims(scopes, requested: nil)
    granted = Scopes.list(scopes)
    claims = { "sub" => uuid }

    if granted.include?(Scopes::PROFILE)
      PROFILE_CLAIMS.each { |claim, attribute| claims[claim] = public_send(attribute) }
      claims["updated_at"] = updated_at.to_i
    end

    if granted.include?(Scopes::EMAIL)
      claims["email"] = email
      claims["email_verified"] = email_verified_at.present?
    end

    asked(requested).each do |claim|
      claims[claim] = public_send(PROFILE_CLAIMS[claim]) if PROFILE_CLAIMS.key?(claim)
    end

    claims.compact
  end

  private

    def activate_once_a_password_exists
      self.activated_at ||= Time.current if password_digest.present?
    end

    def asked(requested)
      return [] if requested.blank?

      Array(requested["userinfo"]&.keys)
    end
end
