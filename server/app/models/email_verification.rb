class EmailVerification < Token
  include MailedLink

  path "verify"

  def self.lifetime
    Rails.configuration.masks.email_verification_lifetime
  end

  def self.open!(actor:, by: nil)
    super(actor: actor, by: by, email: actor.email)
  end

  def self.settle!(secret)
    claimed = claim(secret)
    return nil if claimed.nil?
    return nil unless claimed.addressed?

    claimed.actor.update!(email_verified_at: Time.current)
    claimed.actor
  end

  def address
    (payload || {})["email"]
  end

  def addressed?
    address.present? && actor.email.present? && actor.email == address
  end
end
