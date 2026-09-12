class Invitation < Token
  include MailedLink

  class Refused < StandardError; end

  path "invite"

  def self.lifetime
    Rails.configuration.masks.invitation_lifetime
  end

  def self.open!(actor:, by: nil)
    raise Refused, "#{actor.identifier} has already accepted an invitation" if actor.activated?

    super
  end

  def self.accept!(secret, password)
    claimed = claim(secret)
    return nil if claimed.nil?

    claimed.actor.activate!(password, verifying_email: claimed.delivered?)
    claimed.actor
  end
end
