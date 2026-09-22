class RemoveUpstreamTokens < ActiveRecord::Migration[8.1]
  def change
    remove_column :connections, :access_token, :text
    remove_column :connections, :refresh_token, :text
    remove_column :connections, :access_token_expires_at, :datetime
    remove_column :connections, :scopes, :text, null: false, default: ""
    remove_column :providers, :revocation_url, :string
  end
end
