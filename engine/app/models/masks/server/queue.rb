module Masks
  module Server
    module Queue
      module_function

      def run?
        ::Rails.application.config.active_job.queue_adapter == :solid_queue
      end

      def silence
        ::Rails.configuration.masks.worker_silence
      end

      def wait
        ::Rails.configuration.masks.queue_wait
      end

      def failing_jobs
        ::SolidQueue::FailedExecution.where(created_at: 1.day.ago..).joins(:job)
                                     .distinct.pluck("solid_queue_jobs.class_name").sort
      end

      def worker_heartbeat_at
        ::SolidQueue::Process.where(kind: "Worker").maximum(:last_heartbeat_at)
      end

      def oldest_waiting_at
        ::SolidQueue::ReadyExecution.minimum(:created_at)
      end

      def worker_silent?
        return false unless run? && silence.positive?

        heartbeat = worker_heartbeat_at

        heartbeat.nil? || heartbeat < silence.ago
      end

      def stuck_since
        return nil unless run? && wait.positive?

        oldest = oldest_waiting_at

        oldest if oldest && oldest < wait.ago
      end

      def plain(duration)
        ActiveSupport::Duration.build(duration.to_i).inspect
      end

      def worker_problem
        return "no worker has reported in the last #{plain(silence)}" if worker_silent?

        stuck = stuck_since

        "a job has waited since #{stuck.utc.iso8601}, longer than #{plain(wait)}" if stuck
      end
    end
  end
end
