class CreateTenantLogos < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    create_table :tenant_logos do |t|
      t.references :tenant, null: false, foreign_key: true, index: { unique: true }
      t.string :content_type, null: false
      t.string :digest, null: false
      t.integer :byte_size, null: false
      t.binary :data, null: false

      t.timestamps
    end

    enable_row_level_security(:tenant_logos)

    add_column :tenants, :logo_digest, :string
    add_column :tenants, :accent_color, :string
  end

  def down
    remove_column :tenants, :accent_color
    remove_column :tenants, :logo_digest
    disable_row_level_security(:tenant_logos)
    drop_table :tenant_logos
  end
end
