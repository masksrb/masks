class SigningKey < ApplicationRecord
  include TenantScoped

  SIZE = 2048
  ALGORITHM = "RS256".freeze
  OVERLAP = 24.hours

  encrypts :private_pem

  scope :active, -> { where(retired_at: nil).where.not(activated_at: nil).order(activated_at: :desc) }
  scope :staged, -> { where(activated_at: nil, retired_at: nil).order(created_at: :desc) }
  scope :published, -> { where("retired_at IS NULL OR retired_at > ?", Time.current).order(activated_at: :desc) }

  class << self
    attr_writer :generator

    def generator
      @generator ||= -> { OpenSSL::PKey::RSA.generate(SIZE) }
    end

    def generate!(tenant:, activate: true)
      rsa = generator.call
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

    def stage!(tenant:)
      generate!(tenant: tenant, activate: false)
    end

    def rotate!(tenant:)
      stage!(tenant: tenant).activate!
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

  def certificate
    return OpenSSL::X509::Certificate.new(certificate_pem) if certificate_pem.present?

    issued = self_signed
    update_column(:certificate_pem, issued.to_pem)
    issued
  end

  def sign(claims, typ: "JWT")
    JWT.encode(claims, private_key, algorithm, kid: kid, typ: typ)
  end

  def activate!
    transaction do
      update!(activated_at: Time.current)
      self.class.active.where.not(id: id).update_all(retired_at: OVERLAP.from_now)
    end

    self
  end

  def staged?
    activated_at.nil? && retired_at.nil?
  end

  def active?
    activated_at.present? && retired_at.nil?
  end

  def retired?
    retired_at.present? && retired_at <= Time.current
  end

  private

    def self_signed
      name = OpenSSL::X509::Name.new([ [ "CN", "#{tenant.subdomain} masks" ], [ "O", tenant.name.to_s.presence || tenant.subdomain ] ])

      OpenSSL::X509::Certificate.new.tap do |certificate|
        certificate.version = 2
        certificate.serial = OpenSSL::BN.new(Digest::SHA256.hexdigest(kid)[0, 30], 16)
        certificate.subject = name
        certificate.issuer = name
        certificate.public_key = private_key.public_key
        certificate.not_before = (activated_at || created_at || Time.current) - 1.day
        certificate.not_after = certificate.not_before + 10.years
        certificate.sign(private_key, OpenSSL::Digest.new("SHA256"))
      end
    end
end
