require "test_helper"

module Auth
  module Shared
    module BackupCode
      extend ActiveSupport::Concern

      included do
        describe "BackupCodes" do
          before { client.enable_second_factor! }

          test "10 backup codes must be provided at setup-time" do
            log_in "manager"

            event "backup-codes:replace", updates: { codes: %w[test test] }

            assert_equal 2, entry_json[:warnings].length
            assert_predicate manager.reload.backup_codes, :blank?
            assert_not entry_json.dig(:actor, :savedBackupCodesAt)

            event "backup-codes:replace",
                  updates: {
                    codes: Array.new(10) { SecureRandom.uuid },
                  }

            assert entry_json.dig(:actor, :savedBackupCodesAt)
            assert_predicate manager.reload.backup_codes, :present?
          end

          test "backup codes can be used in lieu of other 2fa options" do
            codes = Array.new(10) { SecureRandom.hex(10) }

            setup_2fa(manager, otp: true, backup_codes: codes)

            log_in "manager"

            event "backup-code:verify", updates: { backupCode: codes.first }

            assert_login
          end

          test "backup codes not in the actor's list are ignored" do
            setup_2fa(manager, otp: true)

            log_in "manager"

            event "backup-code:verify", updates: { code: "invalid-code" }

            refute_settled
          end

          test "backup codes must be replaced after using the last one" do
            codes = [SecureRandom.hex(10)]

            setup_2fa(manager, otp: true, backup_codes: codes)

            log_in "manager"

            event "backup-code:verify", updates: { backupCode: codes.first }

            refute_settled
            assert_prompt "profile"

            event "backup-codes:replace",
                  updates: {
                    otp: {
                      id: manager.otp_secrets.first.public_id,
                      code: manager.otp_secrets.first.otp.now,
                    },
                    codes: Array.new(10) { SecureRandom.uuid },
                  }

            assert_login
          end
        end
      end
    end
  end
end
