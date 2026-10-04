module DatabaseGrants
  class Refused < StandardError; end

  TABLES = "SELECT, INSERT, UPDATE, DELETE".freeze
  SEQUENCES = "USAGE, SELECT, UPDATE".freeze

  class << self
    def grant!(connection, role)
      raise Refused, "MASKS_SERVING_USER names no role to grant to" if role.blank?

      if role == connection.select_value("SELECT current_user")
        raise Refused, "#{role} migrates and serves, so it owns every table and grants would change nothing. " \
                       "Set MASKS_MIGRATION_USER to a role of its own."
      end

      held = connection.quote_column_name(role)

      connection.execute(<<~SQL)
        GRANT USAGE ON SCHEMA public TO #{held};
        GRANT #{TABLES} ON ALL TABLES IN SCHEMA public TO #{held};
        GRANT #{SEQUENCES} ON ALL SEQUENCES IN SCHEMA public TO #{held};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT #{TABLES} ON TABLES TO #{held};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT #{SEQUENCES} ON SEQUENCES TO #{held};
      SQL
    end

    def grant_everywhere!(role)
      ActiveRecord::Base.configurations.configs_for(env_name: ::Rails.env).each do |config|
        ActiveRecord::Base.establish_connection(config)
        grant!(ActiveRecord::Base.connection, role)
        puts "masks: #{role} holds #{TABLES} on #{config.database}"
      end
    ensure
      ActiveRecord::Base.establish_connection
    end
  end
end
