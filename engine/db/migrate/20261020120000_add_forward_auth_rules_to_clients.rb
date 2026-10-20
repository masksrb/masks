class AddForwardAuthRulesToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :forward_auth_rules, :jsonb, null: false, default: []
    add_column :sessions, :second_factor_skipped, :boolean, null: false, default: false
  end
end
