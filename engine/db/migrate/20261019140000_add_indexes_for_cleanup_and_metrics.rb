class AddIndexesForCleanupAndMetrics < ActiveRecord::Migration[8.1]
  def change
    add_index :sessions, %i[tenant_id expires_at]
    add_index :sessions, %i[tenant_id revoked_at], where: "revoked_at IS NOT NULL"
    add_index :sessions, %i[tenant_id created_at]
    add_index :tokens, %i[tenant_id kind created_at]
    add_index :tokens, "tenant_id, LEAST(consumed_at, expires_at)", name: "index_tokens_on_tenant_id_and_ended_at"
    add_index :signing_keys, %i[tenant_id retired_at], where: "retired_at IS NOT NULL"
  end
end
