module Masks
  module Server
    require "test_helper"

    class ConfigurationTest < ActiveSupport::TestCase
      def validate!(cache_store:, mode: :server, local: false)
        config = Configuration.defaults
        config.mode = mode
        config.database = :masks if mode == :engine

        Configuration.validate!(config, local: local, building: false, cache_store: cache_store)
      end

      test "a cache store that every process keeps to itself is refused outside development" do
        %i[memory_store null_store].each do |store|
          error = assert_raises(RuntimeError) { validate!(cache_store: store) }

          assert_match(/every process keeps to itself/, error.message)
          assert_match(store.inspect, error.message)
        end

        assert_raises(RuntimeError) { validate!(cache_store: [ :memory_store, { size: 64.megabytes } ]) }
        assert_raises(RuntimeError) { validate!(cache_store: :null_store, mode: :engine) }
      end

      test "a shared cache store, or none named, passes" do
        assert_nothing_raised { validate!(cache_store: :solid_cache_store) }
        assert_nothing_raised { validate!(cache_store: [ :redis_cache_store, { url: "redis://cache" } ]) }
        assert_nothing_raised { validate!(cache_store: [ :mem_cache_store, "cache:11211" ]) }
        assert_nothing_raised { validate!(cache_store: nil) }
      end

      test "development keeps whatever store it has" do
        assert_nothing_raised { validate!(cache_store: :memory_store, local: true) }
      end
    end
  end
end
