Rails.application.configure do
  held = {
    "ENCRYPTION_PRIMARY_KEY" => ENV["ENCRYPTION_PRIMARY_KEY"].presence,
    "ENCRYPTION_DETERMINISTIC_KEY" => ENV["ENCRYPTION_DETERMINISTIC_KEY"].presence,
    "ENCRYPTION_KEY_DERIVATION_SALT" => ENV["ENCRYPTION_KEY_DERIVATION_SALT"].presence
  }

  unless Rails.env.local? || ENV["SECRET_KEY_BASE_DUMMY"].present?
    missing = held.select { |_, value| value.nil? }.keys

    if missing.any?
      raise "#{missing.join(', ')} #{missing.one? ? 'is' : 'are'} required outside development. " \
            "Without them every encrypted column falls back to a key published in the masks " \
            "source, and anyone with a copy of the database can read what those columns hold."
    end
  end

  config.active_record.encryption.primary_key =
    held["ENCRYPTION_PRIMARY_KEY"] || "development_primary_key_thirty_two_"
  config.active_record.encryption.deterministic_key =
    held["ENCRYPTION_DETERMINISTIC_KEY"] || "development_deterministic_key_32_"
  config.active_record.encryption.key_derivation_salt =
    held["ENCRYPTION_KEY_DERIVATION_SALT"] || "development_key_derivation_salt_"
end
