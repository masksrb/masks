class CreateGroups < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    create_table :groups do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :key, null: false
      t.string :name, null: false

      t.timestamps

      t.index %i[tenant_id key], unique: true
    end

    create_table :group_members do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :group, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :actor, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps

      t.index %i[group_id actor_id], unique: true
    end

    add_column :clients, :allowed_groups, :string, array: true, null: false, default: []

    enable_row_level_security(:groups)
    enable_row_level_security(:group_members)
  end

  def down
    remove_column :clients, :allowed_groups
    disable_row_level_security(:group_members)
    disable_row_level_security(:groups)
    drop_table :group_members
    drop_table :groups
  end
end
