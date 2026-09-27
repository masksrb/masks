module Masks
  module Server
    class AdapterMailer < ApplicationMailer
      def trial(to, adapter:, journey:)
        journey!(journey)

        mail(from: adapter.from, to: to, subject: t("adapter_mailer.test.subject", tenant: @tenant_name)).tap do |message|
          message.delivery_method(*adapter.delivery_method)
        end
      end
    end
  end
end
