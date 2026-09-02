class CreateConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :connections do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :provider, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: true
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :subject, null: false
      t.string :label
      t.text :scopes, null: false, default: ""
      t.text :refresh_token
      t.text :access_token
      t.datetime :access_token_expires_at
      t.datetime :connected_at
      t.datetime :revoked_at
      t.string :revoked_reason

      t.timestamps

      t.index [ :tenant_id, :provider_id, :subject ], unique: true
      t.index :uuid, unique: true
    end
  end
end
