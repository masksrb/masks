module Confirmations
  class << self
    def send_email_code(actor)
      token, code = ConfirmationCode.open!(actor: actor, channel: ConfirmationCode::EMAIL, address: actor.email)

      if ActorMailer.deliverable?
        ActorMailer.confirmation_code(actor, code, tenant_name: Current.tenant&.name).deliver_later
      end

      Event.record!(Event::EMAIL_VERIFICATION_SENT, actor: actor, email: actor.email, by_code: true)

      token
    end

    def send_phone_code(actor)
      token, code = ConfirmationCode.open!(actor: actor, channel: ConfirmationCode::PHONE, address: actor.phone)

      Texting.deliver_later(to: actor.phone, body: I18n.t("texts.code", code: code, tenant: Current.tenant&.name))

      Event.record!(Event::PHONE_VERIFICATION_SENT, actor: actor)

      token
    end

    def request_approval(actor)
      Event.record!(Event::APPROVAL_REQUESTED, actor: actor)

      return unless ActorMailer.deliverable?

      Actor.where("scopes LIKE ?", "%#{Scopes::MANAGE}%").where.not(email_verified_at: nil).find_each do |manager|
        next unless manager.manages?

        ActorMailer.approval_requested(manager, actor, tenant_name: Current.tenant&.name,
                                                       origin: Current.origin).deliver_later
      end
    end

    def approve!(actor, by:)
      actor.update!(pending_approval_at: nil)

      Event.record!(Event::ACTOR_APPROVED, actor: actor, by: by)

      return unless ActorMailer.deliverable? && actor.email.present?

      ActorMailer.approved(actor, tenant_name: Current.tenant&.name, origin: Current.origin).deliver_later
    end
  end
end
