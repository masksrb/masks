class AOneTimePasswordIsUsedOnce < ActiveRecord::Migration[8.1]
  def up
    add_column :actors, :otp_last_step, :bigint
  end

  def down
    remove_column :actors, :otp_last_step
  end
end
