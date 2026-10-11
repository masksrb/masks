class IndexPendingApprovals < ActiveRecord::Migration[8.1]
  def change
    add_index :actors, %i[tenant_id pending_approval_at], where: "pending_approval_at IS NOT NULL"
  end
end
