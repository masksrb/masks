class CreateHealthChecks < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    create_table :health_checks do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name, null: false
      t.string :status, null: false
      t.string :summary, null: false
      t.jsonb :details, null: false, default: {}
      t.datetime :checked_at, null: false
      t.datetime :changed_at, null: false
      t.timestamps
    end

    add_index :health_checks, %i[tenant_id name], unique: true

    enable_row_level_security(:health_checks)
  end

  def down
    disable_row_level_security(:health_checks)
    drop_table :health_checks
  end
end
