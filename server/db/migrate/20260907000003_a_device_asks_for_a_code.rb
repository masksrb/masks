class ADeviceAsksForACode < ActiveRecord::Migration[8.1]
  def up
    add_column :tokens, :user_code_digest, :string

    add_index :tokens, [ :tenant_id, :user_code_digest ],
              unique: true, where: "user_code_digest IS NOT NULL"
  end

  def down
    remove_index :tokens, [ :tenant_id, :user_code_digest ]
    remove_column :tokens, :user_code_digest
  end
end
