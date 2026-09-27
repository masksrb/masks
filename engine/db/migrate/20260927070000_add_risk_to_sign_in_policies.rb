class AddRiskToSignInPolicies < ActiveRecord::Migration[8.1]
  def change
    change_table :sign_in_policies do |t|
      t.boolean :refuse_breached_passwords, null: false, default: false
      t.integer :risk_step_up_at
      t.integer :risk_refuse_at
    end

    add_column :tenants, :risky_networks, :text
  end
end
