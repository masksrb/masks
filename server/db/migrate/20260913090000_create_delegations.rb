class CreateDelegations < ActiveRecord::Migration[8.1]
  include TenantIsolation

  def up
    change_table :providers do |t|
      t.boolean :delegates, null: false, default: false
      t.string :delegated_scopes, null: false, default: ""
      t.jsonb :delegation_params, null: false, default: {}
      t.string :resource_url
      t.string :registration_url
      t.datetime :registered_at
    end

    change_table :connections do |t|
      t.text :access_token
      t.text :refresh_token
      t.datetime :access_token_expires_at
      t.string :delegated_scopes
      t.datetime :tokens_refreshed_at
    end

    create_table :delegations do |t|
      t.references :tenant, null: false, foreign_key: true
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :client, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: true
      t.references :connection, null: false, foreign_key: true
      t.string :scopes, null: false, default: ""
      t.datetime :consented_at, null: false
      t.datetime :released_at
      t.datetime :revoked_at
      t.string :revoked_reason

      t.timestamps

      t.index %i[tenant_id uuid], unique: true
      t.index %i[client_id actor_id connection_id], unique: true, where: "revoked_at IS NULL",
                                                    name: "index_delegations_one_live"
    end

    enable_row_level_security(:delegations)
  end

  def down
    disable_row_level_security(:delegations)
    drop_table :delegations

    change_table :connections do |t|
      t.remove :access_token, :refresh_token, :access_token_expires_at, :delegated_scopes, :tokens_refreshed_at
    end

    change_table :providers do |t|
      t.remove :delegates, :delegated_scopes, :delegation_params, :resource_url, :registration_url, :registered_at
    end
  end
end
