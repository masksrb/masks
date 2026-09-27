class AddIdleAccounts < ActiveRecord::Migration[8.1]
  def change
    change_table :tenants do |t|
      t.integer :idle_after
      t.string :idle_action
    end

    change_table :actors do |t|
      t.datetime :last_active_at
      t.datetime :idle_warned_at
    end
  end
end
