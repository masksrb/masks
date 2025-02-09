module Masks
  class OtpSecret < ApplicationRecord
    self.table_name = "masks_otp_secrets"

    belongs_to :actor

    validates :secret, presence: true, uniqueness: true
    validates :public_id, presence: true, uniqueness: true
    validates :issuer, presence: true

    after_initialize :generate_defaults

    def public_json
      { id: public_id, name:, created_at: }
    end

    def verify_otp(code)
      return false unless valid?

      verified = otp.verify(code, after: verified_at)

      if verified
        self.verified_at = Time.now.utc
        self.save
      end
    end

    def svg(**opts)
      if uri
        qrcode = RQRCode::QRCode.new(uri)
        qrcode.as_svg(**opts)
      end
    end

    def code
      otp.now
    end

    def otp
      ROTP::TOTP.new(secret, issuer:) if secret
    end

    def uri
      otp.provisioning_uri(actor.uuid) if otp && actor
    end

    private

    def generate_defaults
      self.public_id ||= SecureRandom.uuid
      self.secret ||= ROTP::Base32.random
      self.issuer ||= Masks.conf.otp_issuer
    end
  end
end
