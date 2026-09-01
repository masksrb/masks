class AddPayloadToTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :tokens, :payload, :jsonb
  end
end
