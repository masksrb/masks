class AddAppsRequireSecondFactorToSignInPolicies < ActiveRecord::Migration[8.1]
  def change
    add_column :sign_in_policies, :apps_require_second_factor, :boolean, null: false, default: false
  end
end
