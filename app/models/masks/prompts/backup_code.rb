module Masks
  module Prompts
    class BackupCode
      include Masks::Prompt

      match { client.allow_backup_codes? }

      event "backup-codes:replace", if: :change_2fa? do
        unless actor.save_backup_codes(updates["codes"])
          actor.errors.full_messages.each { |error| warn! error }
        end
      end

      event "backup-code:verify", if: :on_2fa? do
        verify_backup_code
      end
    end
  end
end
