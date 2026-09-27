class AddInvitedAtToMemberships < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    add_column :memberships, :invited_at, :datetime

    across_tenants(:memberships) do
      execute "UPDATE memberships SET invited_at = created_at WHERE pending AND invited_at IS NULL"
    end
  end

  def down
    remove_column :memberships, :invited_at
  end
end
