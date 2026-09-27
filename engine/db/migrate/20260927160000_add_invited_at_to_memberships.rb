class AddInvitedAtToMemberships < ActiveRecord::Migration[8.1]
  def up
    add_column :memberships, :invited_at, :datetime
    execute "UPDATE memberships SET invited_at = created_at WHERE pending"
  end

  def down
    remove_column :memberships, :invited_at
  end
end
