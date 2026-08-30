class AddProfileClaimsAndRequestedClaims < ActiveRecord::Migration[8.1]
  def change
    change_table :actors, bulk: true do |t|
      t.string :given_name
      t.string :family_name
      t.string :middle_name
      t.string :profile_url
      t.string :picture_url
      t.string :website_url
      t.string :gender
      t.string :birthdate
      t.string :zoneinfo
      t.string :locale
    end

    add_column :tokens, :requested_claims, :jsonb
  end
end
