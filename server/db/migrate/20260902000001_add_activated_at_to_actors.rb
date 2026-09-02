class AddActivatedAtToActors < ActiveRecord::Migration[8.1]
  def up
    add_column :actors, :activated_at, :datetime

    execute "UPDATE actors SET activated_at = created_at WHERE password_digest IS NOT NULL"
  end

  def down
    remove_column :actors, :activated_at
  end
end
