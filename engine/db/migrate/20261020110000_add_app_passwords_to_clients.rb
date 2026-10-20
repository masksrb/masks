class AddAppPasswordsToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :app_passwords, :boolean, null: false, default: false
  end
end
