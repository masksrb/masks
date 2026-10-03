class AddRememberingToConsents < ActiveRecord::Migration[8.1]
  def change
    add_column :consents, :authorization_details, :jsonb, null: false, default: []
    add_column :consents, :expires_at, :datetime
    add_column :clients, :consent_lifetime, :integer
  end
end
