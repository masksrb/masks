module LoginStates
  class BackupCode < LoginState
    accepts :backup_code

    def enabled?
      actor&.backup_codes?
    end

    prompts "backup-code" do
      login.first_factored? && !login.second_factored? && requested?
    end

    handles "backup" do
      verify
    end

    handles "use-backup-code" do
      request!
      false
    end

    handles "use-authenticator" do
      forget!
      false
    end

    def verify
      return warn!("missing-first-factor") unless login.first_factored?

      if actor.verify_backup_code(update(:backup_code))
        forget!
        factored! :second_factor, expiry: OneTimePassword::EXPIRY
        login.noted! "otp", "mfa"

        Event.record!(
          Event::BACKUP_CODE_SPENT,
          actor: actor, remaining: actor.backup_codes_remaining
        )

        true
      else
        refused! "backup_code"
        warn! "invalid-backup-code"
        false
      end
    end

    def as_json
      { "backupCodes" => { "remaining" => actor&.backup_codes_remaining } }
    end

    private

      def requested?
        login.store["backup_code"].present?
      end

      def request!
        login.store["backup_code"] = "1"
      end

      def forget!
        login.store.delete("backup_code")
      end
  end
end
