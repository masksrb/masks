class CreateSignalStreams < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    create_table :signal_streams do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :issuer, null: false
      t.string :endpoint_url, null: false
      t.text :authorization_header
      t.jsonb :events_requested, null: false, default: []
      t.string :status, null: false, default: "enabled"
      t.string :status_reason
      t.string :description
      t.datetime :last_delivered_at
      t.string :last_failure

      t.timestamps

      t.index %i[tenant_id uuid], unique: true
    end

    enable_row_level_security(:signal_streams)
  end

  def down
    disable_row_level_security(:signal_streams)
    drop_table :signal_streams
  end
end
