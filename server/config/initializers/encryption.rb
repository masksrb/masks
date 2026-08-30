Rails.application.configure do
  config.active_record.encryption.primary_key =
    ENV.fetch("ENCRYPTION_PRIMARY_KEY", "development_primary_key_thirty_two_")
  config.active_record.encryption.deterministic_key =
    ENV.fetch("ENCRYPTION_DETERMINISTIC_KEY", "development_deterministic_key_32_")
  config.active_record.encryption.key_derivation_salt =
    ENV.fetch("ENCRYPTION_KEY_DERIVATION_SALT", "development_key_derivation_salt_")
end
