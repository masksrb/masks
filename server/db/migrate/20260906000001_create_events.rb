class CreateEvents < ActiveRecord::Migration[8.1]
  include TenantIsolation

  def up
    create_table :events do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :actor, foreign_key: { on_delete: :nullify }
      t.references :by, foreign_key: { to_table: :actors, on_delete: :nullify }
      t.references :client, foreign_key: { on_delete: :nullify }
      t.references :device, foreign_key: { on_delete: :nullify }

      t.string :action, null: false
      t.string :ip_address
      t.string :user_agent
      t.jsonb :details, null: false, default: {}

      t.datetime :created_at, null: false
    end

    add_index :events, [ :tenant_id, :created_at ]
    add_index :events, [ :tenant_id, :actor_id, :created_at ]
    add_index :events, [ :tenant_id, :action, :created_at ]

    enable_row_level_security("events")
  end

  def down
    disable_row_level_security("events")

    drop_table :events
  end
end
