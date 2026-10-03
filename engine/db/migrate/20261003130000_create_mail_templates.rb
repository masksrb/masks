class CreateMailTemplates < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    create_table :mail_templates do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :kind, null: false
      t.string :subject
      t.text :message

      t.timestamps

      t.index %i[tenant_id kind], unique: true
    end

    enable_row_level_security(:mail_templates)
  end

  def down
    disable_row_level_security(:mail_templates)
    drop_table :mail_templates
  end
end
