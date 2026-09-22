class AddSetupTokenToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :setup_token, :text
  end
end
