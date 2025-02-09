require "test_helper"

module Auth
  module Shared
    module LoginLink
      extend ActiveSupport::Concern

      included do
        describe "LoginLinks" do
          test "login-link:password switches to password entry" do
            identify("foobar")
            event "login-link:start"
            assert_prompt "login-code"
            event "login-link:password"
            assert_prompt "first-factor"
          end

          test "login-link:start sends an email" do
            identify("manager")
            event "login-link:start"

            perform_enqueued_jobs
            assert_emails 1
            assert_prompt "login-code"
          end

          test "login-link:start does not send duplicate emails" do
            identify("manager")

            event "login-link:start"
            event "login-link:start"

            perform_enqueued_jobs
            assert_emails 1
            assert_prompt "login-code"
          end

          test "login-link:start does not send emails to invalid addresses" do
            identify("invalid@example.com")

            event "login-link:start"

            assert Masks::LoginLink.none?

            perform_enqueued_jobs
            assert_emails 0
            assert_prompt "login-code"
          end

          test "login-link:start does not send emails to actors with no address" do
            manager.emails.destroy_all

            identify("manager")

            event "login-link:start"

            assert Masks::LoginLink.none?

            perform_enqueued_jobs
            assert_emails 0
            assert_prompt "login-code"
          end

          test "login-link:start uses the identifier to pick the email address" do
            address = "masks@example.com"
            email = manager.emails.for_login.find_by(address:)
            manager.emails.build(address: "another@example.com").for_login.save!

            identify("manager")

            event "login-link:start"

            identify(address)

            event "login-link:start"

            assert email.login_links.for_login.one?

            perform_enqueued_jobs
            assert_emails 1
            assert_prompt "login-code"
          end

          test "login-link:verify authenticates given a valid code" do
            identify("manager")

            event "login-link:start"

            link = manager.login_email.login_links.for_login.active.first

            event "login-link:verify", updates: { code: link.code }

            assert_login
          end

          test "login-link:verify authenticates given a code passed via GET params" do
            identify("manager")
            event "login-link:start"
            link = manager.login_email.login_links.for_login.active.first

            event "login-link:verify", updates: { code: "invalid" }
            refute_settled

            event "login-link:verify", params: { login_code: link.code }
            assert_login
          end
        end
      end
    end
  end
end
