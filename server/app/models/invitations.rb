module Invitations
  def self.open(actor:, invited_by: nil)
    invitation = Invitation.open!(actor: actor, invited_by: invited_by)
    url = invitation.url(Current.origin)

    return { delivered: false, url: url } unless deliverable?(actor)

    ActorMailer.invitation(
      actor, url,
      tenant_name: Current.tenant&.name,
      invited_by: invited_by
    ).deliver_later

    invitation.delivered!

    { delivered: true, url: nil }
  end

  def self.deliverable?(actor)
    ActorMailer.deliverable? && actor.email.present?
  end
end
