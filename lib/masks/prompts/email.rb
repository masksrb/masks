module Masks
  module Prompts
    class Email
      include Masks::Prompt

      setting :email_address, :string
      setting :email_code, :string
      setting :new_email_address, :string
      setting :delete_email_address, :string

      match { current_client.allow_emails? }

      event "email:create", factors: FIRST_OR_SECOND do
        next unless new_email_address

        email =
          current_actor.emails.build(
            address: new_email_address,
          ) if new_email_address
        email&.for_login

        if email&.save
          send_verification(email)
        else
          warn! "email:limit" if email&.too_many?
          warn! "email:invalid"
        end
      end

      event "email:delete", factors: FIRST_OR_SECOND do
        email =
          current_actor.emails.for_login.find_by(
            address: delete_email_address,
          ) if delete_email_address

        email&.permanently_delete
      end

      event "email:notify" do
        send_verify_email
      end

      event "email:verify" do
        verify
      end

      def verify
        return unless match? && email_address

        link =
          current_actor.login_links.active.for_verification.find_by(
            code: email_code,
            email: verified_email,
          )

        if link
          link.verified!

          true
        else
          warn! "invalid-code", email_code
        end
      end

      private

      def verified_email
        @verified_email ||=
          current_actor.emails.for_login.find_by(
            address: email_address,
          ) if email_address
      end

      def send_verify_email
        return unless email_address

        email = current_actor.emails.for_login.find_by(address: email_address)

        send_verification(email) if email
      end

      def send_verification(email)
        if email
             .login_links
             .active
             .for_verification
             .where(
               actor: current_actor,
               client: current_client,
               device: current_device,
             )
             .none?
          link =
            current_actor.login_links.build(
              url: session.rails_request.url,
              client: current_client,
              device: current_device,
              log_in: false,
              email:,
            )
          link.save_and_deliver
        end
      end

      def needs_verification?
        latest_verified_email =
          current_actor
            .emails
            .verified
            .for_login
            .order(verified_at: "desc")
            .first
        !latest_verified_email ||
          latest_verified_email.expired_verification?(client)
      end
    end
  end
end
