class AddConsentRequiredToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :consent_required, :boolean, null: false, default: true
  end
end
