class AddTokenLifetimesToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :access_token_lifetime, :integer
    add_column :clients, :refresh_token_lifetime, :integer
  end
end
