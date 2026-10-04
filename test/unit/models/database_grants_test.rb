require "test_helper"

class DatabaseGrantsTest < ActiveSupport::TestCase
  ANOTHER_ROLE = "masks_owner".freeze

  test "the serving role is handed table and sequence access" do
    skip "this database has no #{ANOTHER_ROLE} role to grant to" unless role?(ANOTHER_ROLE)

    DatabaseGrants.grant!(connection, ANOTHER_ROLE)

    %w[SELECT INSERT UPDATE DELETE].each { |privilege| assert holds?("actors", privilege), privilege }
    %w[TRUNCATE REFERENCES TRIGGER].each { |privilege| assert_not holds?("actors", privilege), privilege }
  end

  test "granting to the role that migrates is refused" do
    refused = assert_raises(DatabaseGrants::Refused) do
      DatabaseGrants.grant!(connection, connection.select_value("SELECT current_user"))
    end

    assert_match "MASKS_MIGRATION_USER", refused.message
  end

  test "granting to nobody is refused" do
    assert_raises(DatabaseGrants::Refused) { DatabaseGrants.grant!(connection, nil) }
  end

  private

    def connection
      ActiveRecord::Base.connection
    end

    def role?(name)
      connection.select_value(ActiveRecord::Base.sanitize_sql([ "SELECT 1 FROM pg_roles WHERE rolname = ?", name ])).present?
    end

    def holds?(table, privilege)
      connection.select_value(
        ActiveRecord::Base.sanitize_sql([ "SELECT has_table_privilege(?, ?, ?)", ANOTHER_ROLE, table, privilege ])
      )
    end
end
