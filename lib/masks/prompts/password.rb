module Masks
  module Prompts
    class Password
      include Masks::Prompt

      setting :password, :string

      def show_settings?
        on_first_factor?
      end

      match { current_client.allow_passwords? }

      event "password:verify", if: :current_actor do
        self.prompt = "first-factor" unless verify
      end

      def verify
        return unless current_client.allow_passwords? && password

        if current_actor&.authenticate(password)
          session[Prompt::FACTOR1] = current_client.expires_at(:password_login)

          true
        else
          warn! "invalid-credentials"

          false
        end
      end
    end
  end
end
