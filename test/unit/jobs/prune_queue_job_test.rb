module Masks
  module Server
    require "test_helper"

    class PruneQueueJobTest < ActiveSupport::TestCase
      def self.queue_connected
        @queue_connected ||= SolidQueue::Record.connects_to(database: { writing: :queue, reading: :queue }) || true
      end

      setup do
        self.class.queue_connected
        clear_queue
      end

      teardown { clear_queue }

      def clear_queue
        SolidQueue::FailedExecution.delete_all
        SolidQueue::Job.delete_all
      end

      def job_rows(count, finished_at:, created_at: finished_at)
        SolidQueue::Job.insert_all(Array.new(count) do
          { queue_name: "maintenance", class_name: "Masks::Server::CleanupJob", active_job_id: SecureRandom.uuid,
            finished_at: finished_at, created_at: created_at, updated_at: created_at }
        end, returning: [ :id ]).rows.flatten
      end

      test "finished jobs older than the retention are removed and younger ones stay" do
        job_rows(3, finished_at: 8.days.ago)
        job_rows(2, finished_at: 1.day.ago)

        PruneQueueJob.perform_now

        assert_equal 2, SolidQueue::Job.count
        assert_equal 0, SolidQueue::Job.where(finished_at: ...7.days.ago).count
      end

      test "failed jobs are kept longer than finished ones, then removed with their failure record" do
        old = job_rows(2, finished_at: nil, created_at: 31.days.ago)
        fresh = job_rows(1, finished_at: nil, created_at: 2.days.ago)

        SolidQueue::FailedExecution.insert_all((old + fresh).map do |id|
          { job_id: id, error: { "exception_class" => "RuntimeError" }, created_at: SolidQueue::Job.find(id).created_at }
        end)

        PruneQueueJob.perform_now

        assert_equal 1, SolidQueue::FailedExecution.count
        assert_equal fresh, SolidQueue::Job.pluck(:id)
      end

      test "the prune is scheduled" do
        recurring = YAML.load_file(::Rails.root.join("config/recurring.yml"), aliases: true).fetch("production")

        assert_equal "Masks::Server::PruneQueueJob", recurring.dig("prune_queue", "class")
      end
    end
  end
end
