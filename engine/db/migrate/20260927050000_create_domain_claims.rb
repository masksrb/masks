class CreateDomainClaims < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    create_table :domain_claims do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :provider, foreign_key: { on_delete: :nullify }
      t.string :domain, null: false
      t.string :token, null: false
      t.datetime :verified_at
      t.datetime :checked_at
      t.datetime :missing_since

      t.timestamps

      t.index %i[tenant_id domain], unique: true
      t.index :domain, unique: true, where: "verified_at IS NOT NULL", name: "index_domain_claims_verified_once"
    end

    enable_row_level_security(:domain_claims)
  end

  def down
    disable_row_level_security(:domain_claims)
    drop_table :domain_claims
  end
end
