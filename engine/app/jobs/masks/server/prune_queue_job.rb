module Masks
  module Server
    class PruneQueueJob < ApplicationJob
      queue_as :maintenance
      across_tenants!

      BATCH = 500

      def perform
        return unless defined?(::SolidQueue::Job)

        settings = ::Rails.configuration.masks

        ::SolidQueue::Job.clear_finished_in_batches(batch_size: BATCH, finished_before: settings.finished_job_retention.ago)
        ::SolidQueue::FailedExecution.where(created_at: ...settings.failed_job_retention.ago).discard_all_in_batches(batch_size: BATCH)
      end
    end
  end
end
