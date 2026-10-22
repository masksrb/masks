class AddPinnedOriginToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :pinned_origin, :string
  end
end
