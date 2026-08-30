class CreateSigningKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :signing_keys do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :kid, null: false
      t.string :algorithm, null: false, default: "RS256"
      t.text :private_pem, null: false
      t.jsonb :public_jwk, null: false
      t.datetime :activated_at
      t.datetime :retired_at

      t.timestamps

      t.index [ :tenant_id, :kid ], unique: true
      t.index [ :tenant_id, :activated_at ]
    end
  end
end
