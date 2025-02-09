module Masks
  module Prompts
    class ResetPassword
      include Masks::Prompt

      setup do
        session.structure do
          key :reset_password, parent: :entry, expiry: Masks::NEVER_EXPIRE
        end
      end

      match { client.allow_passwords? }

      event "password:reset" do
        actor.password = updates["reset"] if updates["reset"]

        next warn! "invalid-password" unless updates["reset"] && actor.save

        warn! "changed-password"

        session[:reset_password] = false

        self.prompt = "reset-password"
      end

      event "password:skip-reset" do
        next unless allow_reset?

        session[:reset_password] = false
      end

      event "password:skip" do
        next unless allow_reset?

        sibling(:profile).requested! if updates["profile"]

        session[:reset_password] = false
      end

      event "password:skip" do
        next unless allow_reset?

        session[:reset_password] = false
      end

      prompt "reset-password" do
        allow_reset?
      end

      def requested!
        session[:reset_password] = true
      end

      private

      def allow_reset?
        session[:reset_password]
      end
    end
  end
end
