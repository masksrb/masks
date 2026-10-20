class AddSourcesToGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :groups, :source, :string, null: false, default: "manual"
    add_column :groups, :rule, :jsonb, null: false, default: []
    add_reference :groups, :provider, foreign_key: { on_delete: :nullify }
    add_column :groups, :upstream_group, :string
    add_column :groups, :parent_labels, :jsonb, null: false, default: []
    add_column :groups, :refreshed_at, :datetime
    add_index :groups, %i[tenant_id source]

    add_column :group_members, :sourced_by, :string

    add_column :connections, :upstream_groups, :jsonb, null: false, default: []
  end
end
