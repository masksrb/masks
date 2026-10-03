class AddAuthorizationDetails < ActiveRecord::Migration[8.1]
  def change
    add_column :tokens, :authorization_details, :jsonb
    add_column :clients, :authorization_details_types, :jsonb, null: false, default: []
    add_column :clients, :authorization_details_schemas, :jsonb, null: false, default: {}
  end
end
