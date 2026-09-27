class AddPendingToMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :memberships, :pending, :boolean, null: false, default: false
  end
end
