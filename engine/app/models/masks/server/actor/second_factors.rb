module Masks
  module Server
    class Actor
      module SecondFactors
        extend ActiveSupport::Concern

        OTP_DRIFT = 30
        BACKUP_CODES = 10
        BACKUP_CODE_BYTES = 8

        included do
          encrypts :otp_secret

          before_save :forget_code_factors_for_new_addresses
        end

        class_methods do
          def digest_backup_code(code)
            Digest::SHA256.hexdigest(code.to_s.strip.downcase.delete("^a-f0-9"))
          end
        end

        def otp?
          otp_enabled_at.present? && otp_secret.present?
        end

        def verified_passkeys?
          passkeys.where(user_verified: true).exists?
        end

        def second_factor?
          otp? || verified_passkeys?
        end

        def email_factor?
          email_factor_at.present? && email.present? && email_verified_at.present?
        end

        def phone_factor?
          phone_factor_at.present? && phone.present? && phone_verified_at.present?
        end

        def verify_otp(code)
          return false unless otp?

          step = otp_step(otp_secret, code)

          step.present? && spend_otp_step(step)
        end

        def adopt_otp!(secret, code)
          return false if otp?

          step = otp_step(secret, code)

          return false if step.nil?

          update!(otp_secret: secret, otp_enabled_at: Time.current, otp_last_step: step)
        end

        def backup_codes?
          backup_code_digests.any?
        end

        def backup_codes_remaining
          backup_code_digests.length
        end

        def generate_backup_codes!
          codes = Array.new(BACKUP_CODES) { SecureRandom.hex(BACKUP_CODE_BYTES) }

          update!(
            backup_code_digests: codes.map { |code| self.class.digest_backup_code(code) },
            backup_codes_generated_at: Time.current
          )

          codes
        end

        def verify_backup_code(code)
          return false unless backup_codes?

          digest = self.class.digest_backup_code(code)
          remaining = backup_code_digests.reject do |held|
            ActiveSupport::SecurityUtils.secure_compare(held.to_s, digest)
          end

          return false if remaining.length == backup_code_digests.length

          update!(backup_code_digests: remaining)
          true
        end

        private

          def otp_step(secret, code)
            totp = ROTP::TOTP.new(secret)
            at = totp.verify(code.to_s.delete("^0-9"), drift_behind: OTP_DRIFT)

            at && at.to_i / totp.interval
          end

          def spend_otp_step(step)
            taken = self.class.where(id: id)
                        .where("otp_last_step IS NULL OR otp_last_step < ?", step)
                        .update_all(otp_last_step: step)

            return false if taken.zero?

            self.otp_last_step = step
            true
          end

          def forget_code_factors_for_new_addresses
            self.email_factor_at = nil if will_save_change_to_email? && !new_record?
            self.phone_factor_at = nil if will_save_change_to_phone? && !new_record?
          end
      end
    end
  end
end
