module Masks
  module Server
    require "test_helper"

    class HealthTest < ActionDispatch::IntegrationTest
      setup do
        @sender = ::Rails.application.config.active_job.queue_adapter
        ::Rails.application.config.active_job.queue_adapter = :solid_queue
      end

      teardown { ::Rails.application.config.active_job.queue_adapter = @sender }

      def failing(names)
        held = HealthController.method(:failing_jobs)
        HealthController.define_singleton_method(:failing_jobs) { names }

        yield
      ensure
        HealthController.define_singleton_method(:failing_jobs, held)
      end

      test "jobs are up when nothing failed in the last day" do
        failing([]) { get "/up/jobs" }

        assert_response :ok
        assert_equal "up", response.body
      end

      test "a job that failed in the last day is named" do
        failing(%w[Masks::Server::CleanupJob]) { get "/up/jobs" }

        assert_response :service_unavailable
        assert_equal "failing in the last day: Masks::Server::CleanupJob", response.body
      end

      test "a server that runs no jobs says so" do
        ::Rails.application.config.active_job.queue_adapter = :test

        get "/up/jobs"

        assert_response :ok
        assert_equal "no jobs run here", response.body
      end
    end
  end
end
