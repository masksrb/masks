module Masks
  module Adapters
    class TwilioAdapter
      include Masks::Adapter

      setting :account_sid, :string, env: "MASKS_TWILIO_ACCOUNT_SID"
      setting :auth_token, :string, env: "MASKS_TWILIO_AUTH_TOKEN"
      setting :service_sid, :string, env: "MASKS_TWILIO_SERVICE_SID"

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
    end
  end
end
