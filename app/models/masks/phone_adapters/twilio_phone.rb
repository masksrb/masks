module Masks
  module PhoneAdapters
    class TwilioPhone < Abstract
      def setup?
        account_sid && auth_token
      end

      def notify(phone)
        @verification ||=
          twilio
            .verify
            .v2
            .services(service_sid)
            .verifications
            .create(to: phone.number, channel: "sms")

        @verification.status == "pending"
      end

      def verify(phone, code)
        @check ||=
          twilio
            .verify
            .v2
            .services(service_sid)
            .verification_checks
            .create(to: phone.number, code:)

        @check.status == "approved"
      end

      private

      def twilio
        @twilio ||= Twilio::REST::Client.new(account_sid, auth_token)
      end

      def account_sid
        install.setting(:phones, :twilio, :account_sid)
      end

      def auth_token
        install.setting(:phones, :twilio, :auth_token)
      end

      def service_sid
        install.setting(:phones, :twilio, :service_sid)
      end
    end
  end
end
