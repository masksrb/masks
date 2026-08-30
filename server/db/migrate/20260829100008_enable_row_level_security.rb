class EnableRowLevelSecurity < ActiveRecord::Migration[8.1]
  include TenantIsolation

  TABLES = %w[signing_keys actors clients tokens sessions consents].freeze

  def up
    TABLES.each { |table| enable_row_level_security(table) }
  end

  def down
    TABLES.each { |table| disable_row_level_security(table) }
  end
end
