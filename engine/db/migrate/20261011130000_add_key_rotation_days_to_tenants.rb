class AddKeyRotationDaysToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :key_rotation_days, :integer
  end
end
