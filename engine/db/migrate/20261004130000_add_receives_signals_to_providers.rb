class AddReceivesSignalsToProviders < ActiveRecord::Migration[8.1]
  def change
    add_column :providers, :receives_signals, :boolean, null: false, default: false
  end
end
