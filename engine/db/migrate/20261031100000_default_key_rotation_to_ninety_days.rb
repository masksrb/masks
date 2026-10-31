class DefaultKeyRotationToNinetyDays < ActiveRecord::Migration[8.1]
  def change
    change_column_default :tenants, :key_rotation_days, from: nil, to: 90
  end
end
