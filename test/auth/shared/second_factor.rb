require "test_helper"

module Auth
  module Shared
    module SecondFactor
      extend ActiveSupport::Concern

      included do
        describe "SecondFactor" do
          before { client.enable_second_factor! }

          test "actors must add a factor + backup codes when required" do
            log_in "manager"

            assert_prompt "profile"
            assert entry_json.dig("extras", "secondFactorRequired")
            refute_settled

            add = Masks::OtpSecret.new

            event "otp:create",
                  updates: {
                    create: {
                      secret: add.secret,
                      code: add.code,
                    },
                  }
            assert_equal 1, manager.reload.otp_secrets.count

            event "backup-codes:replace",
                  updates: {
                    codes: Array.new(10) { SecureRandom.uuid },
                  }
            refute_settled
            event "second-factor:enable"
            assert_settled
          end
        end
      end
    end
  end
end
