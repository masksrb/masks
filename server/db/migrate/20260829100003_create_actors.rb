class CreateActors < ActiveRecord::Migration[8.1]
  def change
    create_table :actors do |t|
      t.references :tenant, null: false, foreign_key: true
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :nickname, null: false
      t.string :name
      t.string :email
      t.string :password_digest
      t.text :scopes, null: false, default: ""
      t.text :otp_secret
      t.datetime :otp_enabled_at
      t.datetime :email_verified_at
      t.datetime :last_login_at

      t.timestamps

      t.index :uuid, unique: true
      t.index [ :tenant_id, :nickname ], unique: true
      t.index [ :tenant_id, :email ]
    end
  end
end
