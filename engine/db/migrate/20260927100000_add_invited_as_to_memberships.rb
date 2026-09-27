class AddInvitedAsToMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :memberships, :invited_as, :string
  end
end
