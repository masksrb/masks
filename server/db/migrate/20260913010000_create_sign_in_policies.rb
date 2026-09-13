class CreateSignInPolicies < ActiveRecord::Migration[8.1]
  include TenantIsolation

  def up
    create_table :sign_in_policies do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name, null: false
      t.boolean :signup, null: false, default: false
      t.string :nickname, null: false, default: "optional"
      t.string :email, null: false, default: "required"
      t.boolean :email_verified, null: false, default: false
      t.string :phone, null: false, default: "off"
      t.boolean :phone_verified, null: false, default: false
      t.integer :password_minimum, null: false, default: 8
      t.boolean :refuse_common_passwords, null: false, default: true
      t.jsonb :first_factors, null: false, default: %w[password passkey provider]
      t.jsonb :second_factors, null: false, default: %w[otp passkey backup_codes]
      t.boolean :second_factor_required, null: false, default: false
      t.jsonb :email_domains, null: false, default: []
      t.jsonb :providers
      t.string :confirmation, null: false, default: "none"
      t.boolean :hidden, null: false, default: false
      t.text :signup_scopes
      t.datetime :archived_at

      t.timestamps

      t.index %i[tenant_id key], unique: true
    end

    enable_row_level_security(:sign_in_policies)

    add_reference :tenants, :sign_in_policy, foreign_key: { on_delete: :nullify }
    add_reference :clients, :sign_in_policy, foreign_key: { on_delete: :nullify }
  end

  def down
    remove_reference :clients, :sign_in_policy
    remove_reference :tenants, :sign_in_policy
    disable_row_level_security(:sign_in_policies)
    drop_table :sign_in_policies
  end
end
