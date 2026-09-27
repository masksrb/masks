module Masks
  module Server
    module Recoveries
      def self.request(identifier:, journey:)
        actor = Actor.locate(identifier)

        return false unless mailable?(actor)

        deliver(PasswordReset.open!(actor: actor), actor, journey)
        noted(actor, nil)
        true
      end

      def self.open(actor:, journey:)
        reset = PasswordReset.open!(actor: actor, by: journey.by)
        noted(actor, journey.by)

        return { delivered: false, url: reset.url(Current.origin) } unless mailable?(actor)

        deliver(reset, actor, journey)

        { delivered: true, url: nil }
      end

      def self.noted(actor, by)
        Event.record!(Event::PASSWORD_RESET_REQUESTED, actor: actor, by: by)
      end

      def self.mailable?(actor)
        ActorMailer.deliverable? && actor.present? && actor.activated? && actor.email.present?
      end

      def self.deliver(reset, actor, journey)
        ActorMailer.password_reset(actor, reset.url(Current.origin), journey: journey).deliver_later

        reset.delivered!
      end
    end
  end
end
