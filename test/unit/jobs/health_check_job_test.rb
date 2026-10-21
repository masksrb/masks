module Masks
  module Server
    require "test_helper"

    class HealthCheckJobTest < ActiveSupport::TestCase
      def counting_server_results
        held = Health.method(:server_results)
        calls = 0
        Health.define_singleton_method(:server_results) { calls += 1; held.call }

        yield -> { calls }
      ensure
        Health.define_singleton_method(:server_results, held)
      end

      test "the schedule stores every check in every tenant and works the server checks out once" do
        other = other_tenant

        counting_server_results do |calls|
          HealthCheckJob.perform_now

          assert_equal 1, calls.call
        end

        assert_equal Health::NAMES.sort, within { HealthCheck.by_name.pluck(:name) }
        assert_equal Health::NAMES.sort, within(other) { HealthCheck.by_name.pluck(:name) }
        assert_equal [], Health.failing_named
      end

      test "a tenant that raises is skipped, the rest are stored, and the failing summary still names them" do
        broken = other_tenant
        held = Health.method(:tenant_results)

        Health.define_singleton_method(:tenant_results) do
          raise "the directory is gone" if Current.tenant.id == broken.id

          held.call.map { |result| result.name == "keys" ? Health.failing("keys", "missing") : result }
        end

        error = assert_raises(ApplicationJob::Incomplete) { HealthCheckJob.perform_now }

        assert_match broken.subdomain, error.message
        assert_equal Health::NAMES.size, within { HealthCheck.count }
        assert_equal 0, within(broken) { HealthCheck.count }
        assert_equal [ "keys (#{@tenant.subdomain})" ], Health.failing_named
        assert_equal 1, within { Event.where(action: Event::HEALTH_FAILING).count }
      ensure
        Health.define_singleton_method(:tenant_results, held)
      end

      test "the schedule runs every ten minutes" do
        schedule = YAML.load_file(::Rails.root.join("config/recurring.yml"), aliases: true).fetch("production")

        assert_equal "Masks::Server::HealthCheckJob", schedule.dig("health", "class")
        assert_equal "every 10 minutes", schedule.dig("health", "schedule")
      end
    end
  end
end
