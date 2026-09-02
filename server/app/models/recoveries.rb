module Recoveries
  def self.request(identifier:)
    actor = Actor.locate(identifier)

    return false unless mailable?(actor)

    deliver(PasswordReset.open!(actor: actor), actor)
    true
  end

  def self.open(actor:, by: nil)
    reset = PasswordReset.open!(actor: actor, by: by)

    return { delivered: false, url: reset.url(Current.origin) } unless mailable?(actor)

    deliver(reset, actor, by)

    { delivered: true, url: nil }
  end

  def self.mailable?(actor)
    ActorMailer.deliverable? && actor.present? && actor.activated? && actor.email.present?
  end

  def self.deliver(reset, actor, by = nil)
    ActorMailer.password_reset(
      actor, reset.url(Current.origin),
      tenant_name: Current.tenant&.name,
      opened_by: by
    ).deliver_later

    reset.delivered!
  end
end
