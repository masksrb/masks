class AddHandshakeReturnToToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :handshake_return_to, :string
  end
end
