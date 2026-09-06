class AddBackchannelLogout < ActiveRecord::Migration[8.1]
  def up
    add_column :clients, :backchannel_logout_uri, :string
    add_column :clients, :backchannel_logout_session_required, :boolean, null: false, default: false

    add_column :sessions, :uuid, :uuid, default: -> { "gen_random_uuid()" }, null: false
    add_column :sessions, :origin, :string
    add_index :sessions, [ :tenant_id, :uuid ], unique: true

    add_reference :tokens, :session, foreign_key: { on_delete: :nullify }
  end

  def down
    remove_reference :tokens, :session
    remove_index :sessions, column: [ :tenant_id, :uuid ]
    remove_column :sessions, :origin
    remove_column :sessions, :uuid
    remove_column :clients, :backchannel_logout_session_required
    remove_column :clients, :backchannel_logout_uri
  end
end
