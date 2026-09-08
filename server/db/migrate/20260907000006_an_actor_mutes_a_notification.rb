class AnActorMutesANotification < ActiveRecord::Migration[8.1]
  def up
    add_column :actors, :muted_notifications, :jsonb, null: false, default: []
  end

  def down
    remove_column :actors, :muted_notifications
  end
end
