module Masks
  module Server
    module Tenancy
      SETTING = "masks.tenant_id".freeze
      POOL_PROBE = "masks.pool_probe".freeze
      POOL_PROBE_ROUNDS = 3

      class Exposed < StandardError
        def initialize(role)
          super(
            "this server connects to Postgres as #{role || 'a role it cannot read back'}, which sees " \
            "through row-level security. Every tenant_isolation policy on the database is decorative " \
            "while it does, and the only thing left between one tenant and another's actors, tokens " \
            "and signing keys is a default scope in Ruby. Connect as a role holding neither SUPERUSER " \
            "nor BYPASSRLS."
          )
        end
      end

      class Owner < StandardError
        def initialize(role)
          super(
            "this server connects to Postgres as #{role}, which owns the tables row-level security " \
            "protects. An owner can switch that protection off with one ALTER TABLE, so a single SQL " \
            "injection would read every tenant. Migrate as a separate role named by " \
            "MASKS_MIGRATION_USER and MASKS_MIGRATION_PASSWORD, and serve as a role that holds only " \
            "the grants bin/rails masks:grants hands it."
          )
        end
      end

      class Pooled < StandardError
        def initialize(message = nil)
          super(
            message ||
            "this server reaches Postgres through a pooler that hands out a different server " \
            "connection for each transaction. The tenant masks sets on one connection is gone from " \
            "the next, so a query would see no tenant's rows, or another tenant's. Connect masks to " \
            "Postgres directly, or run the pooler in session mode."
          )
        end
      end

      class << self
        def switch(tenant)
          raise ArgumentError, "no tenant" if tenant.nil?

          isolated!

          return yield tenant if Current.tenant&.id == tenant.id

          held = Current.tenant

          enter(tenant)

          begin
            yield tenant
          ensure
            enter(held)
          end
        end

        def clear!
          enter(nil, for_transaction: false)
        end

        def isolated!
          return true if @isolated

          held = role_privileges

          raise Exposed, held&.fetch("rolname", nil) unless held && held["bypasses"] == false
          raise Owner, held["rolname"] if held["owns"] && guards_ownership?
          raise Pooled if pooled?

          @isolated = true
        end

        def recheck!
          @isolated = nil
        end

        def pooled?
          return false if connection_pool.size < 2

          POOL_PROBE_ROUNDS.times do
            mine = SecureRandom.hex(8)
            connection.exec_query("SELECT set_config($1, $2, false)", "probe", [ POOL_PROBE, mine ])

            return false unless touched_another_connection?

            return true unless connection.select_value("SELECT current_setting('#{POOL_PROBE}', true)") == mine
          end

          false
        rescue ActiveRecord::ConnectionTimeoutError
          false
        end

        def role_privileges
          connection.select_one(<<~SQL)
            SELECT rolname, rolsuper OR rolbypassrls AS bypasses,
                   EXISTS (SELECT 1 FROM pg_class WHERE relrowsecurity AND relowner = pg_roles.oid) AS owns
            FROM pg_roles WHERE rolname = current_user
          SQL
        end

        def guards_ownership?
          !::Rails.env.local? && !Server.engine?
        end

        def adopt(connection)
          return unless masks?(connection)

          connection.exec_query("SELECT set_config($1, $2, false)", "tenant", [ SETTING, Current.tenant&.id.to_s ])
        rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionFailed
          nil
        end

        def masks?(connection)
          database = Server.config.database

          return true if database.nil?

          pool = connection.pool

          pool.respond_to?(:db_config) && pool.db_config.name == database.to_s
        end

        private

          def connection
            ApplicationRecord.connection
          end

          def connection_pool
            ApplicationRecord.connection_pool
          end

          def enter(tenant, for_transaction: connection.transaction_open?)
            Current.tenant = tenant

            connection.exec_query(
              "SELECT set_config($1, $2, $3)", "tenant",
              [ SETTING, tenant&.id.to_s, for_transaction ]
            )

            connection.clear_query_cache
          rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionFailed
            nil
          end

          def touched_another_connection?
            other = connection_pool.checkout

            return false if other.equal?(connection)

            other.exec_query("SELECT set_config($1, $2, false)", "probe", [ POOL_PROBE, "another connection" ])
            true
          ensure
            connection_pool.checkin(other) if other
          end
      end
    end
  end
end
