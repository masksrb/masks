class AddAuthenticatedAtToTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :tokens, :authenticated_at, :datetime
  end
end
