class CreateConsents < ActiveRecord::Migration[8.1]
  def change
    create_table :consents do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.text :scopes, null: false, default: ""
      t.jsonb :audience, null: false, default: []
      t.datetime :revoked_at

      t.timestamps

      t.index [ :actor_id, :client_id ], unique: true
    end
  end
end
