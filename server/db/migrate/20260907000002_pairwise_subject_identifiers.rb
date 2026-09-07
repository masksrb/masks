class PairwiseSubjectIdentifiers < ActiveRecord::Migration[8.1]
  include TenantIsolation

  def up
    add_column :clients, :subject_type, :string, null: false, default: "public"
    add_column :clients, :sector_identifier_uri, :string
    add_column :tenants, :pairwise_salt, :text

    create_table :subjects do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { on_delete: :cascade }

      t.string :sector, null: false
      t.string :sub, null: false

      t.timestamps
    end

    add_index :subjects, [ :tenant_id, :actor_id, :sector ], unique: true
    add_index :subjects, [ :tenant_id, :sub ], unique: true

    enable_row_level_security("subjects")
  end

  def down
    disable_row_level_security("subjects")

    drop_table :subjects

    remove_column :tenants, :pairwise_salt
    remove_column :clients, :sector_identifier_uri
    remove_column :clients, :subject_type
  end
end
