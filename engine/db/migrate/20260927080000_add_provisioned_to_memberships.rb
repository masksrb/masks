class AddProvisionedToMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :memberships, :provisioned, :boolean, null: false, default: false
  end
end
