class AddFirstFactorToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :first_factor, :string
    add_column :sessions, :provider_id, :bigint
  end
end
