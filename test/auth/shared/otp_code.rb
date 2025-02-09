require "test_helper"

module Auth
  module Shared
    module OtpCode
      extend ActiveSupport::Concern

      included do
        describe "OtpCodes" do
          before { client.enable_second_factor! }

          test "otp codes must be valid to be added" do
            travel_to Time.parse("2024-11-17T19:57:11+0000")

            log_in "manager"

            event "otp:create",
                  updates: {
                    create: {
                      secret: "JBSWY3DPEHPK3PXP",
                      code: "247085",
                    },
                  }
            assert manager.otp_secrets.count == 0
            assert_warning "invalid-code:247085"

            event "otp:create",
                  updates: {
                    create: {
                      secret: "JBSWY3DPEHPK3PXP",
                      code: "247086",
                    },
                  }
            assert manager.otp_secrets.count == 1
          end

          test "saved secrets can be used after verification" do
            setup_2fa manager, otp: true

            otp = manager.otp_secrets.first
            id = otp.public_id

            log_in "manager"
            assert_prompt "second-factor"

            event "otp:verify", updates: { otp: { id:, code: "123456" } }
            refute_settled

            event "otp:verify", updates: { otp: { id:, code: otp.code } }
            assert_login
          end

          test "new secrets require separate credentials to add" do
            setup_2fa manager, otp: true

            log_in "manager"
            assert_prompt "second-factor"

            event "otp:create",
                  updates: {
                    create: {
                      secret: "JBSWY3DPEHPK3PXP",
                      code: "247086",
                    },
                  }
            assert manager.otp_secrets.count == 1
            assert_warning "invalid-factor"

            add = Masks::OtpSecret.new
            otp = manager.otp_secrets.first

            event "otp:create",
                  updates: {
                    otp: {
                      id: otp.public_id,
                      code: otp.code,
                    },
                    create: {
                      secret: add.secret,
                      code: add.code,
                    },
                  }
            assert_equal 2, manager.reload.otp_secrets.count
          end

          test "saved secrets' names can be changed after setup" do
            log_in "manager"

            otp = Masks::OtpSecret.new

            event "otp:create",
                  updates: {
                    create: {
                      secret: otp.secret,
                      code: otp.code,
                    },
                  }

            assert secret = manager.otp_secrets.first

            event "otp:name",
                  updates: {
                    otp: {
                      id: secret.public_id,
                      name: "testing",
                    },
                  }

            assert_equal "testing", secret.reload.name
          end
        end
      end
    end
  end
end
