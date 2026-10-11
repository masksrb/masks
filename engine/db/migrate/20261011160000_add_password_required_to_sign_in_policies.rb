class AddPasswordRequiredToSignInPolicies < ActiveRecord::Migration[8.1]
  def change
    add_column :sign_in_policies, :password_required, :boolean, null: false, default: false
  end
end
