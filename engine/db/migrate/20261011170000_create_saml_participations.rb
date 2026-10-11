class CreateSamlParticipations < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    create_table :saml_participations do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :session, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :client, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name_id, null: false
      t.string :name_id_format, null: false
      t.string :session_index, null: false
      t.datetime :notified_at

      t.timestamps
    end

    add_index :saml_participations, %i[session_id client_id], unique: true
    add_index :saml_participations, %i[client_id name_id]

    enable_row_level_security(:saml_participations)

    add_column :clients, :saml_slo_url, :string
  end

  def down
    remove_column :clients, :saml_slo_url
    disable_row_level_security(:saml_participations)
    drop_table :saml_participations
  end
end
