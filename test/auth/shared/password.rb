require "test_helper"

module Auth
  module Shared
    module Password
      extend ActiveSupport::Concern

      included do
        describe "Passwords" do
          test "prompt is shown after an identifier is added" do
            identify("manager")
            assert_prompt "first-factor"
          end

          test "password:verify rejects invalid passwords" do
            enter
            identify("manager")
            enter_password("invalid")

            assert_warning "invalid-credentials"
            assert_prompt "first-factor"
          end

          test "password:verify rejects passwords for actors with nil passwords" do
            actor = Masks.signup("no-password").tap { |a| a.save! }

            assert_nil actor.password_digest

            enter
            identify("no-password")
            enter_password("invalid")

            assert_warning "invalid-credentials"
            assert_prompt "first-factor"
          end

          test "password:verify rejects invalid passwords for invalid actors" do
            enter
            identify("invalid")
            enter_password("invalid")

            assert_warning "invalid-credentials"
            assert_prompt "first-factor"
          end

          test "password:verify authenticates valid passwords" do
            log_in "manager"

            assert_login
          end
        end
      end
    end
  end
end
