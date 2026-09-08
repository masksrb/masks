require_relative "test_helper"

class TrackerTest < Minitest::Test
  def setup
    @store = Masks::Client::Stores::Memory.new
    @tracker = Masks::Client::Tracker.new(@store)
  end

  def test_an_opened_request_can_be_claimed_once
    opened = @tracker.open(return_to: "/here", verifier: "v")

    claimed = @tracker.claim(opened.id)

    assert_equal opened.id, claimed.id
    assert_equal "/here", claimed[:return_to]
    assert_equal "v", claimed[:verifier]
    assert_nil @tracker.claim(opened.id)
  end

  def test_requests_do_not_collide
    first = @tracker.open(return_to: "/first")
    second = @tracker.open(return_to: "/second")

    refute_equal first.id, second.id
    assert_equal "/second", @tracker.claim(second.id)[:return_to]
    assert_equal "/first", @tracker.claim(first.id)[:return_to]
  end

  def test_an_unknown_or_blank_id_claims_nothing
    @tracker.open(return_to: "/here")

    assert_nil @tracker.claim("nope")
    assert_nil @tracker.claim("")
    assert_nil @tracker.claim(nil)
  end

  def test_an_expired_request_is_gone
    tracker = Masks::Client::Tracker.new(@store, ttl: -1)
    opened = tracker.open(return_to: "/here")

    assert_nil tracker.claim(opened.id)
  end

  def test_the_oldest_requests_are_evicted_past_the_limit
    tracker = Masks::Client::Tracker.new(@store, limit: 2)

    first = tracker.open(return_to: "/1")
    second = tracker.open(return_to: "/2")
    third = tracker.open(return_to: "/3")

    assert_equal 2, tracker.size
    assert_nil tracker.claim(first.id)
    refute_nil tracker.claim(second.id)
    refute_nil tracker.claim(third.id)
  end

  def test_amend_adds_facts_without_moving_the_expiry
    opened = @tracker.open(return_to: "/here")
    amended = @tracker.amend(opened.id, nonce: "n", verifier: "v")

    assert_equal opened.expires_at, amended.expires_at
    assert_equal "/here", amended[:return_to]
    assert_equal "n", @tracker.claim(opened.id)[:nonce]
  end

  def test_amending_something_unknown_does_nothing
    assert_nil @tracker.amend("nope", nonce: "n")
  end

  def test_the_store_is_emptied_rather_than_left_holding_a_husk
    opened = @tracker.open(return_to: "/here")
    @tracker.claim(opened.id)

    assert_empty @store.read
  end
end
