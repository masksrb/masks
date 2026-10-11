class HealthController < ActionController::Base
  def self.databases
    [
      ActiveRecord::Base,
      (SolidQueue::Record if Rails.application.config.active_job.queue_adapter == :solid_queue),
      (SolidCache::Record if defined?(SolidCache::Store) && Rails.cache.is_a?(SolidCache::Store))
    ].compact
  end

  def self.jobs_run?
    Rails.application.config.active_job.queue_adapter == :solid_queue
  end

  def self.failing_jobs
    SolidQueue::FailedExecution.where(created_at: 1.day.ago..).joins(:job)
                               .distinct.pluck("solid_queue_jobs.class_name").sort
  end

  def show
    self.class.databases.each { |record| record.connection_pool.with_connection { |connection| connection.select_value("SELECT 1") } }

    render plain: "up"
  rescue ActiveRecord::ActiveRecordError
    render plain: "down", status: :service_unavailable
  end

  def jobs
    return render(plain: "no jobs run here") unless self.class.jobs_run?

    failing = self.class.failing_jobs

    return render(plain: "up") if failing.empty?

    render plain: "failing in the last day: #{failing.join(', ')}", status: :service_unavailable
  rescue ActiveRecord::ActiveRecordError
    render plain: "down", status: :service_unavailable
  end
end
