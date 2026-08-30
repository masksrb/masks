class AddApprovalToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :approved_at, :datetime
    add_reference :clients, :approved_by, foreign_key: { to_table: :actors }
  end
end
