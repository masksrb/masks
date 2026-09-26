module Masks
  module Server
    module Confirmations
      class << self
        def send_code(actor, channel)
          token, code = ConfirmationCode.open!(actor: actor, channel: channel, address: actor.public_send(channel))

          deliver(channel, actor.public_send(channel), code)

          if channel == ConfirmationCode::EMAIL
            Event.record!(Event::EMAIL_VERIFICATION_SENT, actor: actor, email: actor.email, by_code: true)
          else
            Event.record!(Event::PHONE_VERIFICATION_SENT, actor: actor)
          end

          token
        end

        def deliver(channel, to, code)
          tenant_name = Current.tenant&.name

          if channel == ConfirmationCode::EMAIL
            ActorMailer.confirmation_code(to, code, tenant_name: tenant_name).deliver_later
          else
            Texting.deliver_later(to: to, body: I18n.t("texts.code", code: code, tenant: tenant_name))
          end
        end

        def request_approval(actor)
          Event.record!(Event::APPROVAL_REQUESTED, actor: actor)

          return unless ActorMailer.deliverable?

          Actor.holding(Scopes::MANAGE).where.not(email_verified_at: nil).find_each do |manager|
            ActorMailer.approval_requested(manager, actor, tenant_name: Current.tenant&.name,
                                                           origin: Current.origin).deliver_later
          end
        end

        def approve!(actor, by:)
          actor.update!(pending_approval_at: nil)

          Event.record!(Event::ACTOR_APPROVED, actor: actor, by: by)

          return if actor.email.blank?

          ActorMailer.approved(actor, tenant_name: Current.tenant&.name, origin: Current.origin).deliver_later
        end
      end
    end
  end
end
