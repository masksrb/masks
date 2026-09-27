class AddOrganizationsToPoliciesAndProviders < ActiveRecord::Migration[8.1]
  def change
    add_reference :organizations, :sign_in_policy, foreign_key: { on_delete: :nullify }

    change_table :providers do |t|
      t.references :organization, foreign_key: { on_delete: :cascade }
      t.string :role_claim
      t.jsonb :role_map, null: false, default: {}
      t.string :unmapped_role
    end
  end
end
