class AddEventRetentionToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :event_retention_days, :integer
  end
end
