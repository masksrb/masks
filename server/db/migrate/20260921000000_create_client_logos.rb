class CreateClientLogos < ActiveRecord::Migration[8.1]
  include TenantIsolation

  def up
    create_table :client_logos do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.string :source_uri, null: false
      t.string :content_type, null: false
      t.string :digest, null: false
      t.integer :byte_size, null: false
      t.binary :data, null: false

      t.timestamps

      t.index %i[tenant_id client_id], unique: true
    end

    enable_row_level_security(:client_logos)

    add_column :clients, :logo_digest, :string
  end

  def down
    remove_column :clients, :logo_digest

    disable_row_level_security(:client_logos)
    drop_table :client_logos
  end
end
