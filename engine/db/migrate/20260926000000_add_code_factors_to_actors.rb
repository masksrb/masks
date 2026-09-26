class AddCodeFactorsToActors < ActiveRecord::Migration[8.1]
  def change
    change_table :actors do |t|
      t.datetime :email_factor_at
      t.datetime :phone_factor_at
    end
  end
end
