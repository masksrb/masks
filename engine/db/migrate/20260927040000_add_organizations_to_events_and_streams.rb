class AddOrganizationsToEventsAndStreams < ActiveRecord::Migration[8.1]
  def change
    add_reference :events, :organization, foreign_key: { on_delete: :nullify }, index: false
    add_index :events, %i[tenant_id organization_id created_at]

    add_reference :event_streams, :organization, foreign_key: { on_delete: :cascade }
  end
end
