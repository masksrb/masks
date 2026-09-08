require "test_helper"

class RateLimitTest < ActionDispatch::IntegrationTest
  setup do
    host! host_for(@tenant)
    @actor = create_actor(@tenant)
    Rails.cache.clear
  end

  def attempt(identifier: @actor.nickname, password: "wrong", **headers)
    post "/login", params: { event: "identify", identifier: identifier }, as: :json
    post "/login", params: { event: "password", password: password }, as: :json, headers: headers

    response.status
  end

  def with_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "a flood without a csrf token is rate limited rather than refused as forgery" do
    limit = Rails.configuration.masks.account_attempt_limit

    with_forgery_protection do
      statuses = Array.new(limit + 2) { attempt }

      assert_equal :too_many_requests, Rack::Utils::SYMBOL_TO_STATUS_CODE.key(statuses.last),
                   "the last of #{statuses.length} attempts answered #{statuses.last}"
      assert_includes statuses, 429
    end
  end

  test "the limiter is what refuses, and it refuses before the password is checked" do
    limit = Rails.configuration.masks.account_attempt_limit

    limit.times { attempt }

    assert_equal 429, attempt(password: "password")
    assert_nil within(@tenant) { @actor.reload.last_login_at }
  end

  test "the per-identifier budget is separate from the per-address one" do
    limit = Rails.configuration.masks.account_attempt_limit
    other = create_actor(@tenant, nickname: "second")

    limit.times { attempt }

    assert_equal 429, attempt
    assert_equal 200, attempt(identifier: other.nickname)
  end

  test "one tenant cannot exhaust another's budget" do
    limit = Rails.configuration.masks.account_attempt_limit
    elsewhere = Tenant.create!(subdomain: "acme-#{SecureRandom.hex(4)}", name: "Acme")
    theirs = create_actor(elsewhere)

    limit.times { attempt }
    assert_equal 429, attempt

    host! host_for(elsewhere)
    assert_equal 200, attempt(identifier: theirs.nickname)
  end
end
