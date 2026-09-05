class CreateNamespaces < ActiveRecord::Migration[8.1]
  include TenantIsolation

  def up
    create_table :namespaces do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :client, foreign_key: { on_delete: :nullify }

      t.string :name, null: false
      t.string :resource, null: false
      t.datetime :claimed_at, null: false

      t.timestamps
    end

    add_index :namespaces, [ :tenant_id, :name ], unique: true
    add_index :namespaces, [ :tenant_id, :resource ]

    enable_row_level_security("namespaces")
  end

  def down
    disable_row_level_security("namespaces")

    drop_table :namespaces
  end
end
