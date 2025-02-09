module Masks
  module Prompts
    class BackupCode
      include Masks::Prompt

      setting :backup_code, :string
      setting :new_backup_codes, [:string]

      match { current_client.allow_backup_codes? }

      event "backup-codes:replace", if: :change_2fa? do
        unless current_actor.save_backup_codes(new_backup_codes)
          current_client.errors.full_messages.each { |error| warn! error }
        end
      end

      event "backup-code:verify", if: :on_2fa? do
        verify
      end

      def verify
        return unless current_client.allow_backup_codes? && backup_code

        if current_actor&.verify_backup_code(backup_code)
          session[Prompt::FACTOR2] = current_client.expires_at(:backup_code_2fa)
        else
          warn! "invalid-code", backup_code
        end
      end
    end
  end
end
