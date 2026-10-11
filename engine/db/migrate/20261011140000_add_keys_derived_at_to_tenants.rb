class AddKeysDerivedAtToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :keys_derived_at, :datetime
  end
end
