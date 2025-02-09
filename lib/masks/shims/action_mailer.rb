module Masks
  module Shims
    class ActionMailer
      def initialize(settings)
        @settings = settings
      end

      def deliver!(*args, **opts, &block)
        mailer ? mailer.deliver!(*args, **opts, &block) : InvalidMailer.new
      end

      def mailer
        @mailer ||=
          begin
            name = Masks.conf.email_adapter&.presence

            if Rails.env.development? && !name
              LetterOpener::DeliveryMethod.new({})
            elsif Rails.env.test? && !name
              Mail::TestMailer.new({})
            else
              Masks.adapter(name)&.to_mailer
            end
          end
      end

      class InvalidMailer
        def deliver!(*args)
          Masks.logger.warn(
            "[masks] Attempted to send an email but emails are not configured...",
          )
        end
      end
    end
  end
end
