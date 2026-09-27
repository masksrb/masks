module Masks
  module Server
    module Confirmations
      class << self
        def send_code(actor, channel, journey:)
          token, code = ConfirmationCode.open!(actor: actor, channel: channel, address: actor.public_send(channel))

          deliver(channel, actor.public_send(channel), code, journey: journey)

          if channel == ConfirmationCode::EMAIL
            Event.record!(Event::EMAIL_VERIFICATION_SENT, actor: actor, email: actor.email, by_code: true)
          else
            Event.record!(Event::PHONE_VERIFICATION_SENT, actor: actor)
          end

          token
        end

        def deliver(channel, to, code, journey:)
          if channel == ConfirmationCode::EMAIL
            ActorMailer.confirmation_code(to, code, journey: journey).deliver_later
          else
            Texting.deliver_later(to: to, body: I18n.t("texts.code", code: code, tenant: journey.heading))
          end
        end

        def request_approval(actor, journey:)
          Event.record!(Event::APPROVAL_REQUESTED, actor: actor)

          return unless ActorMailer.deliverable?

          Actor.holding(Scopes::MANAGE).where.not(email_verified_at: nil).find_each do |manager|
            ActorMailer.approval_requested(manager, actor, journey: journey).deliver_later
          end
        end

        def approve!(actor, journey:)
          actor.update!(pending_approval_at: nil)

          Event.record!(Event::ACTOR_APPROVED, actor: actor, by: journey.by)

          return if actor.email.blank?

          ActorMailer.approved(actor, journey: journey).deliver_later
        end
      end
    end
  end
end
