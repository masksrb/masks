class Actor < ApplicationRecord
  include TenantScoped

  has_secure_password validations: false

  encrypts :otp_secret

  has_many :tokens, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :consents, dependent: :destroy

  validates :nickname, presence: true,
                       uniqueness: { scope: :tenant_id, case_sensitive: false },
                       format: { with: /\A[a-z0-9][a-z0-9._-]*\z/i }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  normalizes :nickname, with: ->(value) { value.to_s.strip }
  normalizes :email, with: ->(value) { value.to_s.strip.downcase.presence }

  class << self
    def authenticate(identifier, password)
      actor = find_by(nickname: identifier.to_s.strip) ||
              find_by(email: identifier.to_s.strip.downcase)

      return burn(password) if actor.nil? || actor.password_digest.blank?

      actor.authenticate(password.to_s) || nil
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

  def scope_list
    list = Scopes.list(scopes)

    list.empty? ? Scopes::STANDARD.dup : list
  end

  def permitted_scopes(requested)
    Scopes.granted(requested, scope_list)
  end

  def grant!(requested)
    update!(scopes: Scopes.join(scope_list | Scopes.list(requested)))
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

    def asked(requested)
      return [] if requested.blank?

      Array(requested["userinfo"]&.keys)
    end
end
