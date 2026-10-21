class HealthController < ActionController::Base
  def self.databases
    [
      ActiveRecord::Base,
      (SolidQueue::Record if Masks::Server::Queue.run?),
      (SolidCache::Record if defined?(SolidCache::Store) && Rails.cache.is_a?(SolidCache::Store))
    ].compact
  end

  def show
    self.class.databases.each { |record| record.connection_pool.with_connection { |connection| connection.select_value("SELECT 1") } }

    problem = Masks::Server::Queue.worker_problem

    return render(plain: with_checks("down: #{problem}"), status: :service_unavailable) if problem

    render plain: with_checks("up")
  rescue ActiveRecord::ActiveRecordError
    render plain: "down", status: :service_unavailable
  end

  def jobs
    return render(plain: "no jobs run here") unless Masks::Server::Queue.run?

    failing = Masks::Server::Queue.failing_jobs

    return render(plain: "up") if failing.empty?

    render plain: "failing in the last day: #{Masks::Server::JobFailures.named(failing).join(', ')}", status: :service_unavailable
  rescue ActiveRecord::ActiveRecordError
    render plain: "down", status: :service_unavailable
  end

  private

    def with_checks(line)
      failing = Masks::Server::Health.failing_named

      failing.empty? ? line : "#{line}\nfailing checks: #{failing.join(', ')}"
    end
end
