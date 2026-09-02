class PasswordReset < Token
  include MailedLink

  path "reset"

  def self.lifetime
    Rails.configuration.masks.password_reset_lifetime
  end

  def self.settle!(secret, password)
    claimed = claim(secret)
    return nil if claimed.nil?

    claimed.actor.reset_password!(password, verifying_email: claimed.delivered?)
    claimed.actor
  end
end
