class BackfillActivatedAtAcrossTenants < ActiveRecord::Migration[8.1]
  include TenantIsolation

  def up
    across_tenants(:actors) do
      execute <<~SQL
        UPDATE actors
           SET activated_at = created_at
         WHERE password_digest IS NOT NULL
           AND activated_at IS NULL
      SQL
    end
  end

  def down
  end
end
