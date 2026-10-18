class CreateReleasedNicknames < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    create_table :released_nicknames do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :actor, foreign_key: { on_delete: :nullify }, index: false
      t.string :nickname, null: false
      t.datetime :released_at, null: false
    end

    add_index :released_nicknames, %i[tenant_id nickname], unique: true
    add_index :released_nicknames, :released_at

    enable_row_level_security(:released_nicknames)
  end

  def down
    disable_row_level_security(:released_nicknames)
    drop_table :released_nicknames
  end
end
