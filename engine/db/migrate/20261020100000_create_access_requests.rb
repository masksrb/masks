class CreateAccessRequests < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    create_table :access_requests do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :actor, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :client, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :decided_by, foreign_key: { to_table: :actors, on_delete: :nullify }, index: false
      t.string :label
      t.datetime :granted_at
      t.datetime :declined_at
      t.timestamps
    end

    add_index :access_requests, %i[tenant_id actor_id client_id], unique: true,
              where: "granted_at IS NULL AND declined_at IS NULL", name: "index_access_requests_on_open"
    add_index :access_requests, %i[tenant_id client_id]
    add_index :access_requests, :created_at

    enable_row_level_security(:access_requests)
  end

  def down
    disable_row_level_security(:access_requests)
    drop_table :access_requests
  end
end
