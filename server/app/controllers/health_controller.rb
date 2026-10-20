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

  def self.worker_heartbeat_at
    SolidQueue::Process.where(kind: "Worker").maximum(:last_heartbeat_at)
  end

  def self.oldest_waiting_at
    SolidQueue::ReadyExecution.minimum(:created_at)
  end

  def self.worker_problem
    return nil unless jobs_run?

    silence = Rails.configuration.masks.worker_silence
    wait = Rails.configuration.masks.queue_wait

    if silence.positive?
      heartbeat = worker_heartbeat_at

      return "no worker has reported in the last #{plain(silence)}" if heartbeat.nil? || heartbeat < silence.ago
    end

    if wait.positive?
      oldest = oldest_waiting_at

      return "a job has waited since #{oldest.utc.iso8601}, longer than #{plain(wait)}" if oldest && oldest < wait.ago
    end

    nil
  end

  def self.plain(duration)
    ActiveSupport::Duration.build(duration.to_i).inspect
  end

  def show
    self.class.databases.each { |record| record.connection_pool.with_connection { |connection| connection.select_value("SELECT 1") } }

    problem = self.class.worker_problem

    return render(plain: "down: #{problem}", status: :service_unavailable) if problem

    render plain: "up"
  rescue ActiveRecord::ActiveRecordError
    render plain: "down", status: :service_unavailable
  end

  def jobs
    return render(plain: "no jobs run here") unless self.class.jobs_run?

    failing = self.class.failing_jobs

    return render(plain: "up") if failing.empty?

    render plain: "failing in the last day: #{Masks::Server::JobFailures.named(failing).join(', ')}", status: :service_unavailable
  rescue ActiveRecord::ActiveRecordError
    render plain: "down", status: :service_unavailable
  end
end
