require "test_helper"

class EnvTest < MasksTestCase
  setup do
    Masks.conf.db.name = nil
    Masks.conf.db.queue = nil
  end

  teardown { Rails.env = "test" }

  test "db_name(:primary) in test + sqlite3" do
    Masks.conf.db.adapter = "sqlite3"
    assert_equal "data/test.masks.sqlite3", Masks.conf.db_name(:primary)
  end

  test "db_name(:primary) in dev + sqlite3" do
    Masks.conf.db.adapter = "sqlite3"
    Rails.env = "development"
    assert_equal "data/development.masks.sqlite3", Masks.conf.db_name(:primary)
  end

  test "db_name(:primary) in prod + sqlite3" do
    Masks.conf.db.adapter = "sqlite3"
    Rails.env = "production"
    assert_equal "data/masks.sqlite3", Masks.conf.db_name(:primary)
  end

  test "db_name(:primary) in test + postgres" do
    Masks.conf.db.adapter = "postgresql"
    assert_equal "masks_test", Masks.conf.db_name(:primary)
  end

  test "db_name(:primary) in dev + postgres" do
    Masks.conf.db.adapter = "postgresql"
    Rails.env = "development"

    assert_equal "masks_development", Masks.conf.db_name(:primary)
  end

  test "db_name(:primary) in prod + postgres" do
    Masks.conf.db.adapter = "postgresql"
    Rails.env = "production"

    assert_equal "masks", Masks.conf.db_name(:primary)
  end

  test "db_apapter(:primary) is extracted from a supplied URL" do
    Masks.conf.db.url = "postgres://localhost"

    assert_equal "postgresql", Masks.conf.db_adapter(:primary)

    Masks.conf.db.url = "sqlite://localhost"

    assert_equal "sqlite3", Masks.conf.db_adapter(:primary)

    Masks.conf.db.adapter = "mysql"

    assert_equal "mysql", Masks.conf.db_adapter(:primary)
  end

  test "db_apapter(:queue) is nil if not enabled" do
    assert_nil Masks.conf.db_adapter(:queue)

    Masks.conf.db.queue = { url: "postgres://postgres/masks" }
  end

  test "db_enabled?(:queue) returns true if a URL exists for the type" do
    assert_not Masks.conf.db_enabled?(:queue)

    Masks.conf.db.queue = { url: "postgres://postgres/masks" }

    assert_equal "postgresql", Masks.conf.db_adapter(:queue)
  end
end
