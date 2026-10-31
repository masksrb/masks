module Masks
  module Server
    require "test_helper"

    class ThrottleTest < ActiveSupport::TestCase
      setup { Throttle.reset! }

      teardown do
        ENV.delete("MASKS_TOKEN_LIMIT")
        ::Rails.configuration.masks.config_path = nil
        Throttle.reset!
      end

      def declare(yaml)
        path = File.join(Dir.mktmpdir, "masks.yml")
        File.write(path, yaml)
        ::Rails.configuration.masks.config_path = path
        Throttle.reset!
      end

      test "every budget has a default, a window, a variable, and a line for the reference" do
        Throttle::DEFAULTS.each do |budget|
          assert_operator budget.to, :>=, 1, budget.key
          assert_operator budget.within, :>=, 1.minute, budget.key
          assert_match(/\AMASKS_[A-Z_]+\z/, budget.variable, budget.key)
          assert_includes budget.reference, "`#{budget.variable}`"
          assert_includes budget.reference, budget.about
        end

        assert_equal Throttle::DEFAULTS.size, Throttle.reference.size
        assert_equal 10, Throttle.limit(:attempt)
        assert_equal({ to: 60, within: 1.minute }, Throttle.limits(:token))
      end

      test "a budget nobody declared raises, naming the ones that exist" do
        error = assert_raises(Throttle::Invalid) { Throttle.limit(:tokens) }

        assert_match "no limit is called tokens", error.message
        assert_match "token,", error.message
      end

      test "the environment sets a budget, and wins over the declared file" do
        declare("limits:\n  token: 5\n  claim: 9\n")

        assert_equal 5, Throttle.limit(:token)
        assert_equal 9, Throttle.limit(:claim)
        assert_equal 60, Throttle.limit(:pushed_authorization)

        ENV["MASKS_TOKEN_LIMIT"] = "7"
        Throttle.reset!

        assert_equal 7, Throttle.limit(:token)
        assert_equal 9, Throttle.limit(:claim)
      end

      test "a budget that is not a whole number of one or more is refused, wherever it was set" do
        declare("limits:\n  token: lots\n")
        assert_match "limits.token", assert_raises(Throttle::Invalid) { Throttle.limit(:token) }.message

        declare("limits:\n  token: 0\n")
        assert_match "1 or more", assert_raises(Throttle::Invalid) { Throttle.limit(:token) }.message

        declare("limits:\n  tokens: 5\n")
        assert_match "tokens, which do not exist", assert_raises(Throttle::Invalid) { Throttle.limit(:token) }.message

        ENV["MASKS_TOKEN_LIMIT"] = "-3"
        ::Rails.configuration.masks.config_path = nil
        Throttle.reset!
        assert_match "MASKS_TOKEN_LIMIT", assert_raises(Throttle::Invalid) { Throttle.limit(:token) }.message
      end

      test "a declared file with no limits, or none at all, leaves the defaults" do
        declare("name: Home\n")
        assert_equal 60, Throttle.limit(:token)

        ::Rails.configuration.masks.config_path = "/nowhere/masks.yml"
        Throttle.reset!
        assert_equal 60, Throttle.limit(:token)
      end

      test "a hand-counted budget is exceeded once its count reaches the limit, and crowded once it passes it" do
        ::Rails.cache.clear
        by = "probe-#{SecureRandom.hex(4)}"

        assert_not Throttle.exceeded?(:claim, by)

        Throttle.limit(:claim).times { Throttle.count!(:claim, by) }

        assert Throttle.exceeded?(:claim, by)
        assert_not Throttle.exceeded?(:claim, by, times: 2)
        assert_not Throttle.exceeded?(:claim_ceiling, by)

        Throttle.limit(:claim).times { assert_not Throttle.crowded?(:claim, "all-#{by}") }
        assert Throttle.crowded?(:claim, "all-#{by}")
      end

      test "a hand-counted budget shares the key of a controller's rate_limit when it names the same scope" do
        assert_equal "rate-limit:masks/server/logins:identifier:1:ada",
                     Throttle.key(:account_attempt, "1:ada", scope: "masks/server/logins", named: "identifier")
        assert_equal "rate-limit:masks/server/logins:1:10.0.0.1", Throttle.key(:attempt, "1:10.0.0.1", scope: "masks/server/logins")
        assert_equal "rate-limit:masks/server/claim:claims", Throttle.key(:claim, "claims")
      end

      test "reaching a budget is recorded once per address and window, with the budget's name" do
        ::Rails.cache.clear

        within do
          3.times { Throttle.hit!(:token, address: "198.51.100.7") }
          Throttle.hit!(:token, address: "198.51.100.8")
          Throttle.hit!(:revocation, address: "198.51.100.7")

          reached = Event.where(action: Event::LIMIT_REACHED).order(:id).to_a

          assert_equal 3, reached.size
          assert_equal %w[token token revocation], reached.map { |event| event.details["limit"] }
          assert_includes Event::GRAVE, Event::LIMIT_REACHED
        end
      end

      test "reaching a budget outside a tenant is only logged" do
        assert_nothing_raised { Throttle.hit!(:claim, address: "198.51.100.7") }
      end
    end
  end
end
