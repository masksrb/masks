class CreatePasskeys < ActiveRecord::Migration[8.1]
  include TenantIsolation

  def up
    add_column :actors, :webauthn_id, :string

    create_table :passkeys do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: true

      t.string :name, null: false
      t.string :external_id, null: false
      t.text :public_key, null: false
      t.bigint :sign_count, null: false, default: 0
      t.string :aaguid
      t.boolean :discoverable, null: false, default: false
      t.boolean :user_verified, null: false, default: false
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :passkeys, [ :tenant_id, :external_id ], unique: true

    enable_row_level_security("passkeys")
  end

  def down
    disable_row_level_security("passkeys")

    drop_table :passkeys
    remove_column :actors, :webauthn_id
  end
end
