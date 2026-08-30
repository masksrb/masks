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

  def claims(scopes)
    granted = Scopes.list(scopes)
    claims = { "sub" => uuid }

    if granted.include?(Scopes::PROFILE)
      claims["preferred_username"] = nickname
      claims["name"] = name
    end

    if granted.include?(Scopes::EMAIL)
      claims["email"] = email
      claims["email_verified"] = email_verified_at.present?
    end

    claims.compact
  end
end
