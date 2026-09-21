class ConfirmationCode < Token
  DIGITS = 6
  ATTEMPTS = 5
  RESEND_AFTER = 30.seconds

  EMAIL = "email".freeze
  PHONE = "phone".freeze
  INBOX = "inbox".freeze

  INBOX_WINDOW = 15.minutes
  INBOX_PER_IP = 4

  class << self
    def lifetime
      10.minutes
    end

    def open!(actor:, channel:, address:)
      where(actor_id: actor.id).live.where("payload->>'channel' = ?", channel).update_all(consumed_at: Time.current)

      mint_code!(actor: actor, channel: channel, address: address)
    end

    def open_inbox!(address:, ip: nil)
      inbox.where("payload->>'address' = ?", address).live.update_all(consumed_at: Time.current)

      mint_code!(actor: nil, channel: INBOX, address: address, ip: ip)
    end

    def inbox_crowded?(address:, ip: nil)
      recent = inbox.where(created_at: INBOX_WINDOW.ago..)
      limit = Rails.configuration.masks.recovery_limit

      recent.where("payload->>'address' = ?", address).count >= limit ||
        (ip.present? && recent.where("payload->>'ip' = ?", ip).count >= limit * INBOX_PER_IP)
    end

    def inbox
      where(actor_id: nil).where("payload->>'channel' = ?", INBOX)
    end

    def digest(salt, code)
      OpenSSL::HMAC.hexdigest("SHA256", salt.to_s, code.to_s)
    end

    private

      def mint_code!(actor:, channel:, address:, ip: nil)
        code = SecureRandom.random_number(10**DIGITS).to_s.rjust(DIGITS, "0")
        salt = SecureRandom.hex(16)

        token = mint!(
          actor: actor,
          payload: { "channel" => channel, "address" => address, "salt" => salt,
                     "digest" => digest(salt, code), "attempts" => 0, "ip" => ip }.compact
        )

        [ token, code ]
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
    entered = code.to_s.delete("^0-9")
    matched = entered.length == DIGITS &&
              ActiveSupport::SecurityUtils.secure_compare(self.class.digest(held("salt"), entered), held("digest"))

    with_lock do
      next false unless live?

      attempts = held("attempts").to_i + 1
      spent = matched || attempts >= ATTEMPTS

      update!(payload: payload.merge("attempts" => attempts), consumed_at: spent ? Time.current : nil)

      matched
    end
  end
end
