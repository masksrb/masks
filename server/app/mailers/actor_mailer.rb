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
      subject: t("actor_mailer.invitation.subject", tenant: tenant_name)
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
      subject: t("actor_mailer.password_reset.subject", tenant: tenant_name)
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
      subject: t("actor_mailer.email_verification.subject", tenant: tenant_name)
    )
  end
end
