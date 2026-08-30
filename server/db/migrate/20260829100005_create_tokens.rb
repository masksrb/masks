class CreateTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :tokens do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :type, null: false
      t.references :actor, foreign_key: true
      t.references :client, foreign_key: true
      t.references :parent, foreign_key: { to_table: :tokens }
      t.string :digest, null: false
      t.text :scopes, null: false, default: ""
      t.jsonb :audience, null: false, default: []
      t.string :redirect_uri
      t.string :nonce
      t.string :code_challenge
      t.string :code_challenge_method
      t.datetime :expires_at, null: false
      t.datetime :consumed_at

      t.timestamps

      t.index :digest, unique: true
      t.index [ :tenant_id, :type, :expires_at ]
    end
  end
end
