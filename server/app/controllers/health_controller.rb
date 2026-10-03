class HealthController < ActionController::Base
  def self.databases
    [
      ActiveRecord::Base,
      (SolidQueue::Record if Rails.application.config.active_job.queue_adapter == :solid_queue),
      (SolidCache::Record if defined?(SolidCache::Store) && Rails.cache.is_a?(SolidCache::Store))
    ].compact
  end

  def show
    self.class.databases.each { |record| record.connection_pool.with_connection { |connection| connection.select_value("SELECT 1") } }

    render plain: "up"
  rescue ActiveRecord::ActiveRecordError
    render plain: "down", status: :service_unavailable
  end
end
