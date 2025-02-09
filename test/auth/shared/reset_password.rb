require "test_helper"

module Auth
  module Shared
    module ResetPassword
      extend ActiveSupport::Concern

      included do
        describe "ResetPassword" do
          test "login-link:verify allows prompting for reset password" do
            log_in_via_link(manager, resetPassword: true)

            assert_prompt "reset-password"
          end

          test "reset-password event resets password" do
            log_in_via_link(manager, resetPassword: true)

            event "password:reset", updates: { reset: "testing123" }

            assert_prompt "reset-password"

            assert manager.reload.authenticate("testing123")
          end
        end
      end
    end
  end
end
