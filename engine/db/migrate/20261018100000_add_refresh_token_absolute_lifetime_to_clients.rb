class AddRefreshTokenAbsoluteLifetimeToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :refresh_token_absolute_lifetime, :integer
  end
end
