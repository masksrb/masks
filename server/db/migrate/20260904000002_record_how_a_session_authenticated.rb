class RecordHowASessionAuthenticated < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :amr, :jsonb, null: false, default: []
  end
end
