class AddRecoveryRequestedAtToActors < ActiveRecord::Migration[8.1]
  def change
    add_column :actors, :recovery_requested_at, :datetime
    add_index :actors, %i[tenant_id recovery_requested_at], where: "recovery_requested_at IS NOT NULL"
  end
end
