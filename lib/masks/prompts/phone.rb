module Masks
  module Prompts
    class Phone
      include Masks::Prompt

      setting :phone_number, :string
      setting :phone_code, :string
      setting :retry_phone, :boolean

      setting :new_phone_number, :string
      setting :new_phone_code, :string
      setting :retry_new_phone, :boolean

      setting :delete_phone_number, :string

      match { current_client.allow_phones? }

      setup do
        prompt = self

        session.structure do
          current :phone,
                  parent: :endpoint,
                  expiry: -> { prompt.client.expires_at(:phone_verification) }
        end
      end

      event "phone:send" do
        session[:phone] = phone.number

        next warn! "invalid-phone" if !phone.valid?
        next if phone_notified? && !retry_new_phone?
        next warn! "invalid-phone" unless phone.send_code(client)

        session.phone["sent"] = true
      end

      event "phone:create", if: :change_2fa? do
        verify_phone_with_code(phone, new_phone_code)
        expire_notification(phone) unless auth.warnings
      end

      event "phone:verify", if: :on_2fa? do
        verify
      end

      event "phone:delete", if: :change_2fa? do
        phone = current_actor&.phones.find_by(number: delete_phone_number)
        phone.destroy

        expire_notification(phone)
      end

      def verify
        return unless current_client.allow_phones? && phone_number

        verify_phone_with_code(verified_phone, phone_code)
      end

      def verify_phone_with_code(phone, code)
        if phone.verify_code(code)
          session[Prompt::FACTOR2] = current_client.expires_at(:phone_2fa)
        else
          warn! "invalid-code", code
        end
      end

      private

      def phone
        @phone ||=
          Masks::Phone.build(actor: current_actor, number: new_phone_number)
      end

      def verified_phone
        @verified_phone ||= current_actor&.phones.find_by(number: phone_number)
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
