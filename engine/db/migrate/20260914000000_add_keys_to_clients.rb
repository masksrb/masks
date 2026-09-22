class AddKeysToClients < ActiveRecord::Migration[8.1]
  def change
    change_table :clients do |t|
      t.jsonb :jwks
      t.string :jwks_uri
    end
  end
end
