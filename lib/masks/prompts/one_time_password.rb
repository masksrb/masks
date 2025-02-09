module Masks
  module Prompts
    class OneTimePassword
      include Masks::Prompt

      setting :otp_id, :string
      setting :otp_code, :string
      setting :otp_name, :string

      setting :new_otp_secret, :string
      setting :new_otp_code, :string

      setting :delete_otp_id, :string

      match { current_client.allow_otp? }

      event "otp:create", if: :change_2fa? do
        verify_otp_with_code(otp_secret, new_otp_code)
      end

      event "otp:verify", if: :on_2fa? do
        verify_otp
      end

      event "otp:name" do
        verified_otp_secret.name = otp_name
        verified_otp_secret.save
      end

      event "otp:delete", if: :change_2fa? do
        current_actor.otp_secrets.find_by(public_id: delete_otp_id)&.destroy
      end

      def verify
        return unless current_client.allow_otp? && otp_code

        otp_secret = verified_otp_secret

        if otp_secret&.verify_otp(otp_code)
          session[Prompt::FACTOR2] = current_client.expires_at(:otp_2fa)
        else
          warn! "invalid-code", otp_code
        end
      end

      def verify_otp_with_code(otp_secret, code)
        if otp_secret&.verify_otp(code)
          session[Prompt::FACTOR2] = current_client.expires_at(:otp_2fa)
        else
          warn! "invalid-code", code
        end
      end

      private

      def otp_secret
        @otp_secret ||=
          Masks::OtpSecret.new(actor: current_actor, secret: new_otp_secret)
      end

      def verified_otp_secret
        @verified_otp_secret ||=
          current_actor.otp_secrets.find_by(public_id: otp_id) if otp_id
      end
    end
  end
end
