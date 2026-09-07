class ATokenIsBoundToAKey < ActiveRecord::Migration[8.1]
  def up
    add_column :tokens, :jkt, :string
    add_column :clients, :dpop_bound_access_tokens, :boolean, null: false, default: false
  end

  def down
    remove_column :clients, :dpop_bound_access_tokens
    remove_column :tokens, :jkt
  end
end
