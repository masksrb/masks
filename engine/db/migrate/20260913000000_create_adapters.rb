class CreateAdapters < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  SMTP = %i[mail_from smtp_address smtp_port smtp_username smtp_password
            smtp_authentication smtp_domain smtp_tls].freeze

  def up
    create_table :adapters do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :service, null: false
      t.string :kind, null: false
      t.string :key, null: false
      t.string :name, null: false
      t.jsonb :settings, null: false, default: {}
      t.text :secrets
      t.boolean :primary, null: false, default: false
      t.datetime :archived_at

      t.timestamps

      t.index %i[tenant_id key], unique: true
      t.index %i[tenant_id kind], unique: true, where: "\"primary\" AND archived_at IS NULL",
                                  name: "index_adapters_one_primary_per_kind"
    end

    enable_row_level_security(:adapters)

    SMTP.each { |column| remove_column :tenants, column }
  end

  def down
    disable_row_level_security(:adapters)
    drop_table :adapters

    change_table :tenants do |t|
      t.string :mail_from
      t.string :smtp_address
      t.integer :smtp_port
      t.string :smtp_username
      t.text :smtp_password
      t.string :smtp_authentication
      t.string :smtp_domain
      t.boolean :smtp_tls, null: false, default: false
    end
  end
end
