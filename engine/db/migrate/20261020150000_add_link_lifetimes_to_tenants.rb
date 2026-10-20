class AddLinkLifetimesToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :invitation_lifetime, :integer, null: false, default: 7 * 24 * 60 * 60
    add_column :tenants, :organization_invitation_lifetime, :integer, null: false, default: 14 * 24 * 60 * 60
    add_column :tenants, :password_reset_lifetime, :integer, null: false, default: 30 * 60
    add_column :tenants, :email_verification_lifetime, :integer, null: false, default: 2 * 24 * 60 * 60
  end
end
