require "test_helper"

module Auth
  module Shared
    module SmsCode
      include Masks::PhoneAdapters
      extend ActiveSupport::Concern

      NUMBER = "+12345678901"

      included do
        describe "SmsCodes" do
          before do
            client.enable_second_factor!

            setup_2fa(manager, phone: NUMBER)
          end

          test "sms codes can be verified given a pre-registered number" do
            log_in "manager"

            event "phone:send", updates: { phone: NUMBER }
            event "phone:verify",
                  updates: {
                    phone: {
                      number: NUMBER,
                      code: TestPhone.verifications[NUMBER],
                    },
                  }

            assert_login
          end

          test "sms codes are useless when the feature is disabled" do
            client.update(allow_phones: false)

            log_in "manager"

            event "phone:send", updates: { phone: NUMBER }
            assert_not TestPhone.verifications[NUMBER]
            event "phone:verify",
                  updates: {
                    phone: {
                      number: NUMBER,
                      code: TestPhone.verifications[NUMBER],
                    },
                  }

            assert_prompt "second-factor"
            refute_settled
          end

          test "invalid codes are useless" do
            log_in "manager"

            event "phone:send", updates: { phone: { number: NUMBER } }
            event "phone:verify",
                  updates: {
                    phone: {
                      number: NUMBER,
                      code: "invalid",
                    },
                  }

            assert_prompt "second-factor"
            assert_warning "invalid-code:invalid"
            refute_settled
          end

          test "twilio can be used for verification" do
            Masks.installation.modify(
              phones: {
                adapter: "twilio",
                twilio: {
                  service_sid: "53rv1c3",
                  account_sid: "123",
                  auth_token: "xyz",
                },
              },
            )

            travel_to Time.parse("2024-12-03T18:51:10.017Z")
            freeze_time

            log_in "manager"

            VCR.use_cassette("twilio-send") do
              event "phone:send", updates: { phone: { number: NUMBER } }
            end

            VCR.use_cassette("twilio-verify") do
              event "phone:verify",
                    updates: {
                      phone: {
                        number: NUMBER,
                        code: "288720",
                      },
                    }
            end

            assert_login
          end
        end
      end
    end
  end
end
