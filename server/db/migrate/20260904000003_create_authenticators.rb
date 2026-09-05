class CreateAuthenticators < ActiveRecord::Migration[8.1]
  def change
    change_column_null :passkeys, :name, true

    create_table :authenticators do |t|
      t.string :aaguid, null: false
      t.string :name, null: false
      t.string :source, null: false
      t.text :icon
      t.string :certification
      t.jsonb :statuses, null: false, default: []
      t.datetime :compromised_at

      t.timestamps
    end

    add_index :authenticators, :aaguid, unique: true
  end
end
