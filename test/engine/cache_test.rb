require_relative "test_helper"

class CacheTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  ISSUER = "https://auth.example.test/demo".freeze

  class Recording < ActiveSupport::Cache::MemoryStore
    attr_reader :written

    def initialize(...)
      super
      @written = []
    end

    def write(key, value, **options)
      @written << [ key, value ]
      super
    end
  end

  setup do
    @store = Recording.new
    @cache = Masks::Rails::Cache.new(@store)
  end

  def tokens(access_token = "access-#{SecureRandom.hex(4)}")
    Masks::Client::Tokens.new(
      "access_token" => access_token, "refresh_token" => "rotated-#{SecureRandom.hex(4)}", "expires_in" => 3600
    )
  end

  test "requests that refresh one token at once refresh it once and share the result" do
    calls = Queue.new
    started = Queue.new
    fresh = tokens

    leader = Thread.new do
      @cache.renew(ISSUER, "spent") do
        started << true
        calls << :leader
        sleep 0.2
        Masks::Rails::Renewal.renewed(fresh, { "sub" => "actor-1" })
      end
    end

    started.pop

    follower = @cache.renew(ISSUER, "spent") do
      calls << :follower
      Masks::Rails::Renewal.refused
    end

    assert_equal :renewed, leader.value.outcome
    assert_equal :renewed, follower.outcome
    assert_equal fresh.access_token, follower.tokens.access_token
    assert_equal fresh.obtained_at, follower.tokens.obtained_at
    assert_equal({ "sub" => "actor-1" }, follower.identity)
    assert_equal [ :leader ], Array.new(calls.size) { calls.pop }
  end

  test "a refusal is shared too, so no other request spends the token again" do
    @cache.renew(ISSUER, "spent") { Masks::Rails::Renewal.refused }

    assert_equal :refused, @cache.renew(ISSUER, "spent") { flunk "refreshed twice" }.outcome
  end

  test "an outage is not remembered, so the next request tries again" do
    @cache.renew(ISSUER, "spent") { Masks::Rails::Renewal.unreachable }

    assert_equal :renewed, @cache.renew(ISSUER, "spent") { Masks::Rails::Renewal.renewed(tokens, nil) }.outcome
  end

  test "a request that waits on a refresh that never finishes gives up as an outage" do
    claim = Masks::Rails::Cache.key("refreshing", ISSUER, "spent")
    @store.write(claim, 1, expires_in: 30)

    Thread.new do
      sleep 0.1
      @store.delete(claim)
    end

    assert_equal :unreachable, @cache.renew(ISSUER, "spent") { flunk "refreshed while another held the claim" }.outcome
  end

  test "the cache holds no token anyone can read, and a result opens only with the token it replaced" do
    fresh = tokens("readable-access-token")

    @cache.renew(ISSUER, "spent-refresh-token") { Masks::Rails::Renewal.renewed(fresh, { "sub" => "actor-1" }) }

    @store.written.each do |key, value|
      assert_match(/\Amasks:\h{64}\z/, key)
      refute_includes value.to_s, "readable-access-token"
      refute_includes value.to_s, "spent-refresh-token"
      refute_includes value.to_s, fresh.refresh_token
    end

    result = Masks::Rails::Cache.key("refreshed", ISSUER, "spent-refresh-token")
    @store.write(Masks::Rails::Cache.key("refreshed", ISSUER, "other"), @store.read(result))

    assert_equal :unreachable, @cache.renew(ISSUER, "other") { flunk "a result was trusted with the wrong key" }.outcome
  end

  test "a cache that raises is an outage, never a repeat" do
    cache = Masks::Rails::Cache.new(RaisingCache.new)
    logout = Masks::Client::Logout.new("jti" => "j-1", "sub" => "actor-1", "exp" => Time.now.to_i + 60)

    assert_raises(Masks::Rails::Cache::Unavailable) { cache.first?("proof", expires_in: 60) }
    assert_raises(Masks::Rails::Cache::Unavailable) { cache.first_logout?(ISSUER, logout) }
    assert_raises(Masks::Rails::Cache::Unavailable) { cache.departed?(ISSUER, { "sub" => "actor-1" }, since: 0) }
  end

  test "a cache that swallows its errors, as Rails.cache does, is still told apart from a repeat" do
    cache = Masks::Rails::Cache.new(SwallowingCache.new)

    assert_raises(Masks::Rails::Cache::Unavailable) { cache.first?("proof", expires_in: 60) }

    assert @cache.first?("proof", expires_in: 60)
    assert_not @cache.first?("proof", expires_in: 60)
  end

  test "a refresh whose result the cache cannot keep still hands back its tokens" do
    store = Recording.new
    def store.write(key, value, **options) = options[:unless_exist] ? super : raise(IOError, "connection refused")
    fresh = tokens

    renewal = Masks::Rails::Cache.new(store).renew(ISSUER, "spent") { Masks::Rails::Renewal.renewed(fresh, nil) }

    assert_equal fresh.access_token, renewal.tokens.access_token
  end

  test "a logout token is first once" do
    logout = Masks::Client::Logout.new("jti" => "j-1", "sub" => "actor-1", "exp" => Time.now.to_i + 60)

    assert @cache.first_logout?(ISSUER, logout)
    assert_not @cache.first_logout?(ISSUER, logout)
  end

  test "a logout token is remembered for ten minutes, or until two minutes after it expires" do
    soon = Masks::Client::Logout.new("jti" => "j-1", "sub" => "actor-1", "exp" => Time.now.to_i + 60)
    late = Masks::Client::Logout.new("jti" => "j-2", "sub" => "actor-1", "exp" => Time.now.to_i + 3600)

    @cache.first_logout?(ISSUER, soon)
    @cache.first_logout?(ISSUER, late)

    travel 9.minutes do
      assert_not @cache.first_logout?(ISSUER, soon)
    end

    travel 11.minutes do
      assert @cache.first_logout?(ISSUER, soon)
    end

    travel 61.minutes do
      assert_not @cache.first_logout?(ISSUER, late)
    end

    travel 63.minutes do
      assert @cache.first_logout?(ISSUER, late)
    end
  end

  test "a logout reaches sessions that began before it, by sid or by subject" do
    before = Masks::Rails::Cache.now - 1

    @cache.depart!(ISSUER, Masks::Client::Logout.new("jti" => "j-1", "sub" => "actor-1", "sid" => "s-1"))

    assert @cache.departed?(ISSUER, { "sub" => "actor-1", "sid" => "s-1" }, since: before)
    assert_not @cache.departed?(ISSUER, { "sub" => "actor-1", "sid" => "s-2" }, since: before)
    assert_not @cache.departed?(ISSUER, { "sub" => "actor-1", "sid" => "s-1" }, since: Masks::Rails::Cache.now + 1)
    assert_not @cache.departed?("https://elsewhere.test", { "sub" => "actor-1", "sid" => "s-1" }, since: before)

    @cache.depart!(ISSUER, Masks::Client::Logout.new("jti" => "j-2", "sub" => "actor-2"))

    assert @cache.departed?(ISSUER, { "sub" => "actor-2", "sid" => "s-9" }, since: before)
  end
end
