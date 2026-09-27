class CreateOrganizations < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    create_table :organizations do |t|
      t.references :tenant, null: false, foreign_key: true
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :key, null: false
      t.string :name, null: false
      t.jsonb :roles, null: false, default: []
      t.datetime :archived_at

      t.timestamps

      t.index %i[tenant_id key], unique: true
      t.index %i[tenant_id uuid], unique: true
    end

    create_table :memberships do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: { on_delete: :cascade }
      t.references :actor, null: false, foreign_key: { on_delete: :cascade }
      t.references :invited_by, foreign_key: { to_table: :actors, on_delete: :nullify }
      t.string :role, null: false

      t.timestamps

      t.index %i[organization_id actor_id], unique: true
    end

    add_reference :tokens, :organization, foreign_key: { on_delete: :cascade }

    enable_row_level_security(:organizations)
    enable_row_level_security(:memberships)
  end

  def down
    remove_reference :tokens, :organization
    disable_row_level_security(:memberships)
    disable_row_level_security(:organizations)
    drop_table :memberships
    drop_table :organizations
  end
end
