module Invitations
  def self.open(actor:, by: nil)
    invitation = Invitation.open!(actor: actor, by: by)

    Event.record!(Event::INVITATION_SENT, actor: actor, by: by, email: actor.email)

    return { delivered: false, url: invitation.url(Current.origin) } unless mailable?(actor)

    ActorMailer.invitation(
      actor, invitation.url(Current.origin),
      tenant_name: Current.tenant&.name,
      invited_by: by
    ).deliver_later

    invitation.delivered!

    { delivered: true, url: nil }
  end

  def self.mailable?(actor)
    ActorMailer.deliverable? && actor.email.present?
  end
end
