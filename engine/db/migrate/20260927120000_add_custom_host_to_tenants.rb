class AddCustomHostToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :custom_host, :string
    add_index :tenants, :custom_host, unique: true, where: "custom_host IS NOT NULL"
  end
end
