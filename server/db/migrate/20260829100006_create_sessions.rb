class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: true
      t.string :digest, null: false
      t.string :user_agent
      t.string :ip_address
      t.datetime :authenticated_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at

      t.timestamps

      t.index :digest, unique: true
    end
  end
end
