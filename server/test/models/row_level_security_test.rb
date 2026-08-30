require "test_helper"

class RowLevelSecurityTest < ActiveSupport::TestCase
  setup do
    Rails.application.eager_load!

    @tables = ApplicationRecord.descendants
      .select { |model| model.include?(TenantScoped) }
      .map(&:table_name)
      .uniq
  end

  test "there is at least one tenant-scoped table to protect" do
    assert_not_empty @tables
  end

  test "every tenant-scoped table carries an isolation policy" do
    policed = connection.select_values(<<~SQL)
      SELECT tablename FROM pg_policies WHERE policyname = 'tenant_isolation'
    SQL

    assert_empty @tables - policed,
                 "these tables have no tenant_isolation policy in this database, so the only " \
                 "thing separating tenants is the default scope in Ruby"
  end

  test "every tenant-scoped table forces row-level security on its owner" do
    forced = connection.select_values(<<~SQL)
      SELECT relname FROM pg_class WHERE relrowsecurity AND relforcerowsecurity
    SQL

    assert_empty @tables - forced,
                 "row-level security that is not FORCEd does not apply to the table owner, " \
                 "which is the role the application connects as"
  end

  test "the application does not connect as a role that bypasses row-level security" do
    bypasses = connection.select_value(<<~SQL)
      SELECT rolbypassrls OR rolsuper FROM pg_roles WHERE rolname = current_user
    SQL

    assert_not bypasses,
               "the application role can see through row-level security, which makes every " \
               "policy above decorative"
  end

  private

    def connection
      ActiveRecord::Base.connection
    end
end
