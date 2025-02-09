module Masks
  module Prompts
    class ResetPassword
      include Masks::Prompt

      setting :reset_password, :string
      setting :edit_profile, :boolean

      setup do
        session.structure do
          key :reset_password, parent: :endpoint, expiry: Masks::NEVER_EXPIRE
        end
      end

      match { current_client.allow_passwords? }

      event "password:reset" do
        current_actor.password = reset_password if reset_password

        unless reset_password && current_actor.save
          next warn! "invalid-password"
        end

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

        sibling(:profile).requested! if edit_profile

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
