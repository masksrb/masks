class AddInvitedAtToMemberships < ActiveRecord::Migration[8.1]
  def up
    add_column :memberships, :invited_at, :datetime

    select_values("SELECT id FROM tenants").each do |tenant|
      execute "SELECT set_config('masks.tenant_id', '#{Integer(tenant)}', true)"
      execute "UPDATE memberships SET invited_at = created_at WHERE pending AND invited_at IS NULL"
    end
  end

  def down
    remove_column :memberships, :invited_at
  end
end
