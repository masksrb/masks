class AddScopeBounds < ActiveRecord::Migration[8.1]
  def change
    rename_column :clients, :scopes, :allowed_scopes
    add_column :clients, :required_scopes, :text, null: false, default: ""
    add_column :tenants, :dynamic_client_scopes, :text
  end
end
