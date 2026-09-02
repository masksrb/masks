class ActorMailer < ApplicationMailer
  def invitation(actor, url, tenant_name:, invited_by: nil)
    return message unless deliverable?

    @actor = actor
    @url = url
    @tenant_name = tenant_name
    @invited_by = invited_by

    mail(
      from: self.class.from,
      to: actor.email,
      subject: "You have been invited to #{tenant_name}"
    )
  end
end
