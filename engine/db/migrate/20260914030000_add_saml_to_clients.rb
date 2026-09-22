class AddSamlToClients < ActiveRecord::Migration[8.1]
  def change
    change_table :clients do |t|
      t.string :protocol, null: false, default: "oidc"
      t.string :saml_entity_id
      t.text :saml_certificate
      t.string :saml_name_id_format
      t.boolean :saml_requests_signed, null: false, default: false
      t.boolean :saml_idp_initiated, null: false, default: false
      t.jsonb :saml_attributes, null: false, default: {}

      t.index %i[tenant_id saml_entity_id], unique: true, where: "saml_entity_id IS NOT NULL"
    end

    add_column :signing_keys, :certificate_pem, :text
  end
end
