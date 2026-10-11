class AddEnrolledByToClients < ActiveRecord::Migration[8.1]
  def change
    add_reference :clients, :enrolled_by, foreign_key: { to_table: :clients, on_delete: :nullify }, index: true
  end
end
