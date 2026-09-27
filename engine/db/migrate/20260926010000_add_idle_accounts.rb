class AddIdleAccounts < ActiveRecord::Migration[8.1]
  def change
    change_table :tenants do |t|
      t.integer :suspend_after
      t.integer :delete_after
    end

    change_table :actors do |t|
      t.datetime :last_active_at
      t.datetime :idle_warned_at
      t.string :idle_warning
      t.boolean :idle_suspended, default: false, null: false
    end
  end
end
