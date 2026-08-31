class AddPostLogoutRedirectUrisToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :post_logout_redirect_uris, :jsonb, null: false, default: []
  end
end
