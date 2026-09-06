class SignInWithAProvider < ActiveRecord::Migration[8.1]
  def change
    change_table :providers, bulk: true do |t|
      t.string :issuer
      t.string :jwks_uri
      t.jsonb :jwks, null: false, default: {}
      t.datetime :jwks_fetched_at
      t.boolean :signs_in, null: false, default: false
      t.boolean :provisions, null: false, default: false
      t.text :email_domains, null: false, default: ""
      t.text :signup_scopes, null: false, default: ""
    end

    change_table :connections, bulk: true do |t|
      t.string :email
      t.boolean :email_verified, null: false, default: false
      t.datetime :signed_in_at
    end

    add_index :providers, [ :tenant_id, :signs_in ]
  end
end
