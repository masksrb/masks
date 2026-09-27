class AddSessionPolicies < ActiveRecord::Migration[8.1]
  def change
    change_table :sign_in_policies do |t|
      t.integer :session_lifetime
      t.integer :session_idle_timeout
    end

    change_table :sessions do |t|
      t.datetime :last_seen_at
      t.integer :idle_timeout
      t.boolean :bounded, null: false, default: false
    end
  end
end
