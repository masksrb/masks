module Masks
  module Server
    class SenderMailer < ApplicationMailer
      def trial(to, sender:, journey:)
        journey!(journey)

        mail(from: sender.from, to: to, subject: t("sender_mailer.test.subject", tenant: @tenant_name)).tap do |message|
          message.delivery_method(*sender.delivery_method)
        end
      end
    end
  end
end
