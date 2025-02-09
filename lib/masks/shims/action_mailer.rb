module Masks
  module Shims
    class ActionMailer
      def initialize(settings)
        @settings = settings
      end

      def deliver!(*args, **opts, &block)
        mailer.deliver!(*args, **opts, &block)
      end

      def mailer
        case install.setting(:emails, :adapter)
        when "sendmail"
          Mail::Sendmail.new(
            install.setting(:emails, :sendmail).symbolize_keys.compact,
          )
        when "smtp"
          Mail::SMTP.new(
            install
              .setting(:emails, :smtp, default: {})
              .symbolize_keys
              .compact,
          )
        when "dev"
          LetterOpener::DeliveryMethod.new({})
        when "test"
          Mail::TestMailer.new({})
        else
          NilMailer.new
        end
      end

      def install
        Masks.installation
      end

      class NilMailer
        def deliver!(*args)
          nil
        end
      end
    end
  end
end
