module Masks
  module Prompts
    class Phone
      include Masks::Prompt

      match { client.allow_phones? }

      setup do
        prompt = self

        session.structure do
          current :phone,
                  parent: :entry,
                  expiry: -> { prompt.client.expires_at(:phone_verification) }
        end
      end

      event "phone:send" do
        session[:phone] = phone.number

        next warn! "invalid-phone" if !phone.valid?
        next if phone_notified? && !updates.dig("create", "resend")
        next warn! "invalid-phone" unless phone.send_code

        session.phone["sent"] = true
      end

      event "phone:create", if: :change_2fa? do
        verify_phone_with_code(phone, updates.dig("create", "code"))
        expire_notification(phone) unless auth.warnings
      end

      event "phone:verify", if: :on_2fa? do
        verify_phone
      end

      event "phone:delete", if: :change_2fa? do
        verified_phone.destroy

        expire_notification(verified_phone)
      end

      private

      def phone
        @phone ||=
          Masks::Phone.build(actor:, number: updates.dig("create", "number"))
      end

      def phone_notified?
        session.phone["sent"]
      end

      def expire_notification(phone = nil)
        session.phone.with((phone || self.phone).number).clear
      end
    end
  end
end
