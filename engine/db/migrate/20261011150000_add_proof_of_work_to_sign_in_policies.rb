class AddProofOfWorkToSignInPolicies < ActiveRecord::Migration[8.1]
  def change
    add_column :sign_in_policies, :proof_of_work, :integer, null: false, default: 17
  end
end
