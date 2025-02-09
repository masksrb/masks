module Masks
  module Prompts
    class Email
      include Masks::Prompt

      match { client&.allow_emails? }

      event "email:create", factors: FIRST_OR_SECOND do
        next unless updates["create"]

        address = updates.dig("create", "address")
        email = actor.emails.build(address:) if updates["create"]
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
          actor.emails.for_login.find_by(
            address: updates.dig("delete", "address"),
          ) if updates["delete"]

        email&.permanently_delete
      end

      event "email:notify" do
        send_verify_email
      end

      event "email:verify" do
        verify_email
      end

      private

      def send_verify_email
        return unless updates["email"]

        email =
          actor.emails.for_login.find_by(
            address: updates.dig("email", "address"),
          ) if updates["email"]

        send_verification(email) if email
      end

      def send_verification(email)
        if email
             .login_links
             .active
             .for_verification
             .where(actor:, client:, device: device)
             .none?
          link =
            actor.login_links.build(
              path: entry.path,
              params: entry.params,
              client:,
              device:,
              email:,
              log_in: false,
            )
          link.save_and_deliver
        end
      end

      def needs_verification?
        latest_verified_email =
          actor.emails.verified.for_login.order(verified_at: "desc").first
        !latest_verified_email ||
          latest_verified_email.expired_verification?(client)
      end
    end
  end
end
