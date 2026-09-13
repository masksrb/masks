class AddSignupToActors < ActiveRecord::Migration[8.1]
  def change
    add_column :actors, :phone, :string
    add_column :actors, :phone_verified_at, :datetime
    add_column :actors, :signed_up_at, :datetime
    add_column :actors, :pending_approval_at, :datetime

    add_index :actors, %i[tenant_id phone], unique: true, where: "phone IS NOT NULL"
  end
end
