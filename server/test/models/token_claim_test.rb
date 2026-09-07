require "test_helper"

class TokenClaimTest < ActiveSupport::TestCase
  setup do
    @actor = create_actor
    @client = create_client
  end

  def mint(klass = AuthorizationCode, **attributes)
    within { klass.mint!(actor: @actor, client: @client, **attributes) }
  end

  test "claiming returns the record and consumes it in one step" do
    minted = mint
    claimed = within { AuthorizationCode.claim(minted.secret) }

    assert_equal minted.id, claimed.id
    assert claimed.consumed?
    assert within { AuthorizationCode.find(minted.id).consumed? }
  end

  test "a second claim of the same secret returns nothing" do
    minted = mint

    assert within { AuthorizationCode.claim(minted.secret) }
    assert_nil within { AuthorizationCode.claim(minted.secret) }
  end

  test "an expired token cannot be claimed" do
    minted = mint(expires_at: 1.second.ago)

    assert_nil within { AuthorizationCode.claim(minted.secret) }
    assert_not within { AuthorizationCode.find(minted.id).consumed? }
  end

  test "a blank secret claims nothing" do
    assert_nil within { AuthorizationCode.claim(nil) }
    assert_nil within { AuthorizationCode.claim("") }
  end

  test "claiming does not reach a sibling type holding the same digest" do
    minted = mint

    assert_nil within { RefreshToken.claim(minted.secret) }
    assert_not within { AuthorizationCode.find(minted.id).consumed? }
  end

  test "a token of another tenant cannot be claimed" do
    minted = mint

    assert_nil Tenant.switch(other_tenant) { AuthorizationCode.claim(minted.secret) }
    assert_not within { AuthorizationCode.find(minted.id).consumed? }
  end

  test "spent still finds what claim consumed, so replay detection keeps working" do
    minted = mint

    within { AuthorizationCode.claim(minted.secret) }
    spent = within { AuthorizationCode.spent(minted.secret) }

    assert_equal minted.id, spent.id
  end
end

class TokenClaimRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  SCOPED = [ Token, Session, Consent, SigningKey, Actor, Client ].freeze

  setup do
    @actor = create_actor
    @client = create_client
  end

  teardown do
    [ @tenant, other_tenant ].compact.each do |tenant|
      Tenant.switch(tenant) { SCOPED.each(&:delete_all) }
      tenant.destroy
    end

    assert_equal 0, Tenant.count, "a non-transactional test left tenants behind"
  end

  test "two racing claims of one code produce exactly one winner" do
    minted = Tenant.switch(@tenant) { AuthorizationCode.mint!(actor: @actor, client: @client) }
    gate = Concurrent::CountDownLatch.new(1)

    winners = 4.times.map do
      Thread.new do
        gate.wait(5)

        ActiveRecord::Base.connection_pool.with_connection do
          Tenant.switch(@tenant) { AuthorizationCode.claim(minted.secret) }
        end
      end
    end

    gate.count_down
    claimed = winners.map(&:value).compact

    assert_equal 1, claimed.size
    assert_equal minted.id, claimed.first.id
  end
end
