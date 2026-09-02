module Verifications
  def self.open(actor:, by: nil)
    return { delivered: false, url: nil } unless pending?(actor)

    verification = EmailVerification.open!(actor: actor, by: by)

    return { delivered: false, url: verification.url(Current.origin) } unless ActorMailer.deliverable?

    ActorMailer.email_verification(
      actor, verification.url(Current.origin),
      tenant_name: Current.tenant&.name
    ).deliver_later

    verification.delivered!

    { delivered: true, url: nil }
  end

  def self.pending?(actor)
    actor.present? && actor.email.present? && actor.email_verified_at.nil?
  end
end
