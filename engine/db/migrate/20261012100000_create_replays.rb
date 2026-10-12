class CreateReplays < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    create_table :replays do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :kind, null: false
      t.string :digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false
    end

    add_index :replays, %i[tenant_id kind digest], unique: true
    add_index :replays, :expires_at

    enable_row_level_security(:replays)
  end

  def down
    disable_row_level_security(:replays)
    drop_table :replays
  end
end
