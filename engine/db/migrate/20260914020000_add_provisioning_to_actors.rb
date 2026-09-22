class AddProvisioningToActors < ActiveRecord::Migration[8.1]
  def change
    change_table :actors do |t|
      t.string :external_id
      t.datetime :suspended_at

      t.index %i[tenant_id external_id], unique: true, where: "external_id IS NOT NULL"
    end
  end
end
