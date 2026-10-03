class AddMetadataExpiresAtToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :metadata_expires_at, :datetime
  end
end
