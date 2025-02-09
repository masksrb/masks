module Masks
  module Prompts
    class OneTimePassword
      include Masks::Prompt

      match { client.allow_otp? }

      event "otp:create", if: :change_2fa? do
        verify_otp_with_code(otp_secret, updates["create"]&.fetch("code", nil))
      end

      event "otp:verify", if: :on_2fa? do
        verify_otp
      end

      event "otp:name" do
        verified_otp_secret.name = updates.dig("otp", "name")
        verified_otp_secret.save
      end

      event "otp:delete", if: :change_2fa? do
        secret =
          actor.otp_secrets.find_by(
            public_id: updates["delete"]&.fetch("id", nil),
          )
        secret&.destroy
      end

      private

      def otp_secret
        @otp_secret ||=
          Masks::OtpSecret.new(
            actor:,
            secret: updates["create"]&.fetch("secret", nil),
          )
      end
    end
  end
end
