class CreateClients < ActiveRecord::Migration[8.1]
  def change
    create_table :clients do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :client_id, null: false
      t.string :secret_digest
      t.string :name, null: false
      t.jsonb :redirect_uris, null: false, default: []
      t.jsonb :grant_types, null: false, default: [ "authorization_code" ]
      t.jsonb :response_types, null: false, default: [ "code" ]
      t.jsonb :resources, null: false, default: []
      t.text :scopes, null: false, default: ""
      t.string :token_endpoint_auth_method, null: false, default: "client_secret_basic"
      t.string :application_type, null: false, default: "web"
      t.string :client_uri
      t.string :logo_uri
      t.string :tos_uri
      t.string :policy_uri
      t.boolean :dynamic, null: false, default: false
      t.string :registration_token_digest
      t.datetime :secret_expires_at
      t.datetime :archived_at

      t.timestamps

      t.index [ :tenant_id, :client_id ], unique: true
      t.index :registration_token_digest
    end
  end
end
