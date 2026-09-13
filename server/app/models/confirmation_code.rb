class ConfirmationCode < Token
  DIGITS = 6
  ATTEMPTS = 5
  RESEND_AFTER = 30.seconds

  EMAIL = "email".freeze
  PHONE = "phone".freeze

  class << self
    def lifetime
      10.minutes
    end

    def open!(actor:, channel:, address:)
      where(actor_id: actor.id).live.select { |held| held.channel == channel }.each(&:consume!)

      code = SecureRandom.random_number(10**DIGITS).to_s.rjust(DIGITS, "0")
      salt = SecureRandom.hex(16)

      token = mint!(
        actor: actor,
        payload: { "channel" => channel, "address" => address, "salt" => salt,
                   "digest" => digest(salt, code), "attempts" => 0 }
      )

      [ token, code ]
    end

    def digest(salt, code)
      OpenSSL::HMAC.hexdigest("SHA256", salt.to_s, code.to_s)
    end
  end

  def channel
    held("channel")
  end

  def address
    held("address")
  end

  def resendable?
    created_at <= RESEND_AFTER.ago
  end

  def verify(code)
    return false unless live?

    entered = code.to_s.delete("^0-9")
    matched = entered.length == DIGITS &&
              ActiveSupport::SecurityUtils.secure_compare(self.class.digest(held("salt"), entered), held("digest"))

    with_lock do
      attempts = held("attempts").to_i + 1
      spent = matched || attempts >= ATTEMPTS

      update!(payload: payload.merge("attempts" => attempts), consumed_at: spent ? Time.current : nil)
    end

    matched
  end
end
