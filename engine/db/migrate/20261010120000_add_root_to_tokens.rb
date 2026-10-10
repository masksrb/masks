class AddRootToTokens < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    add_reference :tokens, :root, foreign_key: { to_table: :tokens, on_delete: :nullify }, index: false
    add_index :tokens, %i[tenant_id root_id]

    across_tenants(:tokens) do
      execute <<~SQL
        WITH RECURSIVE chains(id, root_id) AS (
          SELECT id, id FROM tokens WHERE parent_id IS NULL
          UNION ALL
          SELECT tokens.id, chains.root_id FROM tokens JOIN chains ON tokens.parent_id = chains.id
        )
        UPDATE tokens SET root_id = chains.root_id
        FROM chains
        WHERE tokens.id = chains.id AND chains.root_id <> tokens.id
      SQL
    end
  end

  def down
    remove_foreign_key :tokens, column: :root_id
    remove_index :tokens, %i[tenant_id root_id]
    remove_column :tokens, :root_id
  end
end
