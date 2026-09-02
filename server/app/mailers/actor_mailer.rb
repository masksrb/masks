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

  def password_reset(actor, url, tenant_name:, opened_by: nil)
    return message unless deliverable?

    @actor = actor
    @url = url
    @tenant_name = tenant_name
    @opened_by = opened_by

    mail(
      from: self.class.from,
      to: actor.email,
      subject: "Reset your #{tenant_name} password"
    )
  end

  def email_verification(actor, url, tenant_name:)
    return message unless deliverable?

    @actor = actor
    @url = url
    @tenant_name = tenant_name

    mail(
      from: self.class.from,
      to: actor.email,
      subject: "Confirm your email address for #{tenant_name}"
    )
  end
end
