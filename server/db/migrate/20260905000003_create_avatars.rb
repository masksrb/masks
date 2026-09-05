class CreateAvatars < ActiveRecord::Migration[8.1]
  include TenantIsolation

  def up
    create_table :avatars do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: true

      t.string :content_type, null: false
      t.string :digest, null: false
      t.integer :byte_size, null: false
      t.binary :data, null: false

      t.timestamps
    end

    add_index :avatars, [ :tenant_id, :actor_id ], unique: true

    enable_row_level_security("avatars")
  end

  def down
    disable_row_level_security("avatars")

    drop_table :avatars
  end
end
