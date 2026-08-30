class CreateTenants < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    create_table :tenants do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :subdomain, null: false
      t.string :name, null: false
      t.jsonb :settings, null: false, default: {}
      t.datetime :archived_at

      t.timestamps

      t.index :uuid, unique: true
      t.index :subdomain, unique: true
    end
  end
end
