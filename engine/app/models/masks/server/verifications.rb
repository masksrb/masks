module Masks
  module Server
    module Verifications
      def self.open(actor:, journey:)
        return { delivered: false, url: nil } unless pending?(actor)

        by = journey.by
        verification = EmailVerification.open!(actor: actor, by: by)

        Event.record!(Event::EMAIL_VERIFICATION_SENT, actor: actor, by: by, email: actor.email)

        return { delivered: false, url: verification.url(Current.origin) } unless ActorMailer.deliverable?

        ActorMailer.email_verification(actor, verification.url(Current.origin), journey: journey).deliver_later

        verification.delivered!

        { delivered: true, url: nil }
      end

      def self.pending?(actor)
        actor.present? && actor.email.present? && actor.email_verified_at.nil?
      end
    end
  end
end
