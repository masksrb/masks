require "test_helper"

class TenantIsolationTest < ActiveSupport::TestCase
  test "rows created under one tenant are invisible to another" do
    create_actor(@tenant, nickname: "owner")

    within(@other) do
      assert_nil Actor.find_by(nickname: "owner")
      assert_equal 0, Actor.count
    end
  end

  test "row-level security hides rows even from an unscoped query" do
    create_actor(@tenant, nickname: "owner")

    within(@other) do
      assert_equal 0, Actor.unscoped.count,
                   "the database, not the default scope, must be what isolates tenants"
    end
  end

  test "switching restores the outer tenant on the way out" do
    within(@tenant) do
      within(@other) do
        assert_equal @other, Current.tenant
      end

      assert_equal @tenant, Current.tenant, "nesting must not blind the caller to its own rows"
    end
  end

  test "switching restores the outer tenant even when the block raises" do
    within(@tenant) do
      assert_raises(RuntimeError) do
        within(@other) { raise "boom" }
      end

      assert_equal @tenant, Current.tenant
    end
  end

  test "a tenant cannot write a row belonging to another" do
    assert_raises(ActiveRecord::StatementInvalid) do
      within(@other) do
        Actor.create!(nickname: "smuggled", password: "password", tenant_id: @tenant.id)
      end
    end
  end

  test "signing keys are per tenant" do
    mine = @tenant.ensure_signing_key!
    theirs = @other.ensure_signing_key!

    assert_not_equal mine.kid, theirs.kid

    within(@other) do
      assert_nil SigningKey.find_by(kid: mine.kid),
                 "one tenant must not be able to see another's signing key"
    end
  end
end
