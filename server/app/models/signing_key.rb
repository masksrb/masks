class SigningKey < ApplicationRecord
  include TenantScoped

  SIZE = 2048
  ALGORITHM = "RS256".freeze
  OVERLAP = 24.hours

  encrypts :private_pem

  scope :active, -> { where(retired_at: nil).where.not(activated_at: nil).order(activated_at: :desc) }
  scope :published, -> { where("retired_at IS NULL OR retired_at > ?", Time.current).order(activated_at: :desc) }

  class << self
    def generate!(tenant:, activate: true)
      rsa = OpenSSL::PKey::RSA.generate(SIZE)
      kid = SecureRandom.uuid

      create!(
        tenant: tenant,
        kid: kid,
        algorithm: ALGORITHM,
        private_pem: rsa.to_pem,
        public_jwk: jwk_for(rsa.public_key, kid),
        activated_at: (Time.current if activate)
      )
    end

    def rotate!(tenant:)
      replacement = generate!(tenant: tenant)
      active.where.not(id: replacement.id).update_all(retired_at: OVERLAP.from_now)
      replacement
    end

    def jwk_for(public_key, kid)
      {
        "kty" => "RSA",
        "use" => "sig",
        "alg" => ALGORITHM,
        "kid" => kid,
        "n" => Base64.urlsafe_encode64(public_key.n.to_s(2), padding: false),
        "e" => Base64.urlsafe_encode64(public_key.e.to_s(2), padding: false)
      }
    end
  end

  def private_key
    @private_key ||= OpenSSL::PKey::RSA.new(private_pem)
  end

  def sign(claims)
    JWT.encode(claims, private_key, algorithm, kid: kid, typ: "JWT")
  end

  def retired?
    retired_at.present? && retired_at <= Time.current
  end
end
