class AddSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :masks_sessions do |t|
      t.string :session_id, null: false
      t.text :data
      t.timestamps
    end

    add_index :masks_sessions, :session_id, unique: true
    add_index :masks_sessions, :updated_at
  end
end
