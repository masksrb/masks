class RequirePushedAuthorizationRequests < ActiveRecord::Migration[8.1]
  def up
    add_column :clients, :require_pushed_authorization_requests, :boolean, null: false, default: false
  end

  def down
    remove_column :clients, :require_pushed_authorization_requests
  end
end
