class AddSamlToProviders < ActiveRecord::Migration[8.1]
  def change
    add_column :providers, :idp_entity_id, :string
    add_column :providers, :idp_sso_url, :string
    add_column :providers, :idp_certificates, :text
    add_column :providers, :metadata_url, :string
    add_column :providers, :metadata_fetched_at, :datetime
    add_column :providers, :name_id_format, :string
  end
end
