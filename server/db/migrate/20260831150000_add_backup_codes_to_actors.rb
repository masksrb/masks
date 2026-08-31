class AddBackupCodesToActors < ActiveRecord::Migration[8.1]
  def change
    add_column :actors, :backup_code_digests, :jsonb, null: false, default: []
    add_column :actors, :backup_codes_generated_at, :datetime
  end
end
