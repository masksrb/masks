class CreateEventStreams < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    create_table :event_streams do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name, null: false
      t.string :url, null: false
      t.text :secret, null: false
      t.jsonb :actions, null: false, default: []
      t.datetime :last_delivered_at
      t.string :last_failure
      t.datetime :archived_at

      t.timestamps

      t.index %i[tenant_id key], unique: true
    end

    enable_row_level_security(:event_streams)
  end

  def down
    disable_row_level_security(:event_streams)
    drop_table :event_streams
  end
end
