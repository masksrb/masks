module Masks
  module Server
    require "test_helper"

    class ReplayTest < ActiveSupport::TestCase
      def first?(id = "jti-1", kind: "assertion", within: "client-1", expires_in: 1.minute, tenant: @tenant)
        within(tenant) { Replay.first?(kind, id, within: within, expires_in: expires_in) }
      end

      test "an id is seen first once, and again only after it expires" do
        assert first?
        assert_not first?

        travel 61.seconds do
          assert first?
          assert_not first?
        end
      end

      test "the kind, the scope, and the tenant each keep their own memory" do
        assert first?
        assert first?(kind: "dpop")
        assert first?(within: "client-2")
        assert first?(within: nil)
        assert first?(tenant: other_tenant)
      end

      test "a stored row holds only a digest of the id" do
        first?("a-secret-jti")

        within { assert_not Replay.where("digest LIKE ?", "%a-secret-jti%").exists? }
      end

      test "pruning drops expired ids in the current tenant only" do
        first?("old", expires_in: 1.minute)
        first?("fresh", expires_in: 1.hour)
        first?("theirs", expires_in: 1.minute, tenant: other_tenant)

        travel 2.minutes do
          PruneReplaysJob.perform_now

          within { assert_equal 1, Replay.count }
          within(other_tenant) { assert_equal 0, Replay.count }
        end
      end

      test "the job runs every hour" do
        held = YAML.load_file(::Rails.root.join("config/recurring.yml"), aliases: true)

        assert_equal "Masks::Server::PruneReplaysJob", held.dig("production", "replays", "class")
      end
    end
  end
end
