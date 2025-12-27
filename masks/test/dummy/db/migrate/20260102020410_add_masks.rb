class AddMasks < ActiveRecord::Migration[8.1]
  def change
    create_table :masks_devices do |t|
      t.string :public_id, null: false
      t.string :user_agent
      t.string :ip_address
      t.string :session_id
      t.bigint :version
      t.text   :captcha

      t.timestamps
      t.datetime :blocked_at

      t.index %i[public_id], unique: true
    end

    create_table :masks_clients do |t|
      t.string :name
      t.string :key

      t.text :settings
      t.timestamps

      t.index %i[key], unique: true
    end
  end
end
