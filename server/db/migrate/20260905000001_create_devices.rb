class CreateDevices < ActiveRecord::Migration[8.1]
  include TenantIsolation

  def up
    create_table :devices do |t|
      t.references :tenant, null: false, foreign_key: true

      t.string :public_id, null: false
      t.string :version, null: false
      t.string :name
      t.string :user_agent
      t.string :ip_address
      t.datetime :last_seen_at, null: false
      t.datetime :blocked_at

      t.timestamps
    end

    add_index :devices, [ :tenant_id, :public_id ], unique: true
    add_index :devices, [ :tenant_id, :last_seen_at ]

    create_table :device_factors do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :device, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: true

      t.string :factor, null: false
      t.datetime :satisfied_at, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :device_factors, [ :device_id, :actor_id, :factor ],
              unique: true, name: "index_device_factors_on_device_and_actor_and_factor"

    add_reference :sessions, :device, foreign_key: true
    add_column :sessions, :device_version, :string

    add_reference :tokens, :device, foreign_key: true

    enable_row_level_security("devices")
    enable_row_level_security("device_factors")
  end

  def down
    disable_row_level_security("device_factors")
    disable_row_level_security("devices")

    remove_reference :tokens, :device
    remove_column :sessions, :device_version
    remove_reference :sessions, :device

    drop_table :device_factors
    drop_table :devices
  end
end
