class AddProtocolsToProviders < ActiveRecord::Migration[8.1]
  def change
    add_column :providers, :protocol, :string, null: false, default: "oidc"
    add_column :providers, :preset, :string
    add_column :providers, :claims, :jsonb, null: false, default: {}
    add_column :providers, :emails_url, :string
    add_column :providers, :token_auth_method, :string, null: false, default: "client_secret_post"
    add_column :providers, :response_mode, :string
    add_column :providers, :team_id, :string
    add_column :providers, :key_id, :string
    add_column :providers, :private_key, :text

    remove_column :providers, :label_claim, :string, null: false, default: "email"

    change_column_null :providers, :authorization_url, true
    change_column_null :providers, :token_url, true
    change_column_null :providers, :client_id, true
  end
end
