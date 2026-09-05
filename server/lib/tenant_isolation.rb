module TenantIsolation
  SETTING = "masks.tenant_id".freeze

  def enable_row_level_security(table)
    execute <<~SQL
      ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
      ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;

      CREATE POLICY tenant_isolation ON #{table}
        USING (tenant_id = NULLIF(current_setting('#{SETTING}', true), '')::bigint)
        WITH CHECK (tenant_id = NULLIF(current_setting('#{SETTING}', true), '')::bigint);
    SQL
  end

  def across_tenants(table)
    execute "ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY"

    yield
  ensure
    execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY"
  end

  def disable_row_level_security(table)
    execute <<~SQL
      DROP POLICY IF EXISTS tenant_isolation ON #{table};
      ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY;
      ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY;
    SQL
  end
end
