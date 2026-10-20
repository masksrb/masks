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

      test "a failing job names the tenants that failed last time" do
        JobFailures.record("Masks::Server::RotateSigningKeysJob", %w[demo acme])

        failing(%w[Masks::Server::CleanupJob Masks::Server::RotateSigningKeysJob]) { get "/up/jobs" }

        assert_response :service_unavailable
        assert_equal "failing in the last day: Masks::Server::CleanupJob, Masks::Server::RotateSigningKeysJob (acme, demo)", response.body
      end

      def queue(heartbeat: nil, oldest: nil)
        held_heartbeat = HealthController.method(:worker_heartbeat_at)
        held_oldest = HealthController.method(:oldest_waiting_at)
        HealthController.define_singleton_method(:worker_heartbeat_at) { heartbeat }
        HealthController.define_singleton_method(:oldest_waiting_at) { oldest }

        yield
      ensure
        HealthController.define_singleton_method(:worker_heartbeat_at, held_heartbeat)
        HealthController.define_singleton_method(:oldest_waiting_at, held_oldest)
      end

      test "the server is down when no worker has reported" do
        queue { get "/up" }

        assert_response :service_unavailable
        assert_equal "down: no worker has reported in the last 5 minutes", response.body
      end

      test "the server is down when the only worker's heartbeat is stale" do
        queue(heartbeat: 6.minutes.ago) { get "/up" }

        assert_response :service_unavailable
        assert_match "no worker has reported", response.body
      end

      test "the server is up with a live worker and an empty queue" do
        queue(heartbeat: 10.seconds.ago) { get "/up" }

        assert_response :ok
        assert_equal "up", response.body
      end

      test "the server is down when a job has waited longer than the queue allows" do
        queue(heartbeat: 10.seconds.ago, oldest: 11.minutes.ago) { get "/up" }

        assert_response :service_unavailable
        assert_match "a job has waited since", response.body
        assert_match "longer than 10 minutes", response.body
      end

      test "a job that has just been queued is not a problem" do
        queue(heartbeat: 10.seconds.ago, oldest: 1.minute.ago) { get "/up" }

        assert_response :ok
      end

      test "the worker check is off when its silence is set to zero" do
        held = ::Rails.configuration.masks.worker_silence
        ::Rails.configuration.masks.worker_silence = 0.seconds

        queue { get "/up" }

        assert_response :ok
      ensure
        ::Rails.configuration.masks.worker_silence = held
      end

      test "a server that runs no jobs does not look for a worker" do
        ::Rails.application.config.active_job.queue_adapter = :test

        get "/up"

        assert_response :ok
        assert_equal "up", response.body
      end
    end
  end
end
