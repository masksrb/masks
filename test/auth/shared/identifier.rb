module Auth
  module Shared
    module Identifier
      extend ActiveSupport::Concern

      included do
        describe "Identifiers" do
          test "nicknames are valid identifiers" do
            assert_login log_in("manager")
          end

          test "emails from the 'login' group are valid identifiers" do
            assert_login log_in("masks@example.com")
          end

          test "authorize returns a nil identifier by default" do
            enter

            assert_prompt "identify"
            assert_nil entry_json[:identifier]
          end

          test "attempts with invalid nicknames return a warning" do
            identify('!@#$%^&*()')

            assert_prompt "identify"
            assert_nil entry_json[:identifier]
            assert_warning "invalid-identifier"
          end

          test "attempts to identify with a non-existent nickname moves to next prompt" do
            identify("foobar")

            refute_prompt "identify"
            assert_equal "foobar", entry_json.dig(:actor, :identifier)
          end

          test "attempts to identify with a non-existent email moves to next prompt" do
            identify("foobar@example.com")

            refute_prompt "identify"
            assert_equal "foobar@example.com",
                         entry_json.dig(:actor, :identifier)
          end

          test "nickname identifiers are ignored when the feature is disabled" do
            client.update!(allow_nicknames: false)

            identify("manager")

            assert_prompt "identify"
            assert_warning "invalid-identifier"
            assert_artifacts devices: 1
          end

          test "email identifiers are ignored when the feature is disabled" do
            client.update!(allow_emails: false)

            identify("masks@example.com")

            assert_prompt "identify"
            assert_warning "invalid-identifier"
            assert_artifacts devices: 1
          end

          test "only emails from the 'login' group are valid identifiers" do
            email = "masks@example.com"
            manager
              .emails
              .for_login
              .find_by!(address: email)
              .update_attribute("group", "test")

            log_in(email)

            refute_settled
          end
        end
      end
    end
  end
end
