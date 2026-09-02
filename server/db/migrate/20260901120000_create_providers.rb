class CreateProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :providers do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name, null: false
      t.string :authorization_url, null: false
      t.string :token_url, null: false
      t.string :revocation_url
      t.string :userinfo_url
      t.string :client_id, null: false
      t.text :client_secret
      t.text :scopes, null: false, default: ""
      t.jsonb :authorize_params, null: false, default: {}
      t.string :subject_claim, null: false, default: "sub"
      t.string :label_claim, null: false, default: "email"
      t.datetime :archived_at

      t.timestamps

      t.index [ :tenant_id, :key ], unique: true
    end
  end
end
