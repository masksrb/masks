class AddRoleToProviders < ActiveRecord::Migration[8.1]
  def up
    add_column :providers, :role, :string, null: false, default: "credential"
    add_column :providers, :trusts_email, :boolean, null: false, default: false

    execute "UPDATE providers SET role = 'delegate' WHERE provisions"

    remove_index :providers, %i[tenant_id signs_in], if_exists: true
    remove_column :providers, :signs_in
    remove_column :providers, :provisions
  end

  def down
    add_column :providers, :signs_in, :boolean, null: false, default: false
    add_column :providers, :provisions, :boolean, null: false, default: false

    execute "UPDATE providers SET provisions = (role = 'delegate'), signs_in = (issuer IS NOT NULL)"

    add_index :providers, %i[tenant_id signs_in]
    remove_column :providers, :trusts_email
    remove_column :providers, :role
  end
end
