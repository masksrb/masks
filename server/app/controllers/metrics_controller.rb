class MetricsController < ActionController::Base
  rate_limit to: 30, within: 1.minute, by: -> { request.remote_ip }, with: -> { head :too_many_requests }

  def show
    expected = ENV["MASKS_METRICS_TOKEN"].to_s
    return head(:not_found) if expected.empty?

    scheme, given = request.authorization.to_s.split(" ", 2)
    return head(:unauthorized) unless scheme == "Bearer" && ActiveSupport::SecurityUtils.secure_compare(given.to_s, expected)

    render plain: Metrics.new.to_s, content_type: "text/plain; version=0.0.4"
  end

  class Metrics
    HOUR = 1.hour

    GAUGES = {
      "masks_actors" => "Accounts in the tenant.",
      "masks_sessions_live" => "Sessions that have not ended.",
      "masks_sign_ins_last_hour" => "Sessions started in the last hour.",
      "masks_sign_ins_refused_last_hour" => "Sign-ins refused in the last hour.",
      "masks_access_tokens_last_hour" => "Access tokens issued in the last hour."
    }.freeze

    def to_s
      tenants = Masks::Server::Tenant.active.order(:subdomain).to_a
      held = tenants.filter_map { |tenant| (counts = counted(tenant)) && [ tenant.subdomain, counts ] }

      lines = [ gauge("masks_tenants", "Tenants this server serves.", [ [ nil, tenants.size ] ]) ]
      GAUGES.each { |name, help| lines << gauge(name, help, held.map { |subdomain, counts| [ subdomain, counts.fetch(name) ] }) }
      lines.concat(jobs)

      lines.join("\n") + "\n"
    end

    private

      def counted(tenant)
        Masks::Server::Tenant.switch(tenant) { counts }
      rescue ActiveRecord::ActiveRecordError
        nil
      end

      def counts
        since = HOUR.ago

        {
          "masks_actors" => Masks::Server::Actor.count,
          "masks_sessions_live" => Masks::Server::Session.live.count,
          "masks_sign_ins_last_hour" => event_count(Masks::Server::Event::SESSION_STARTED, since),
          "masks_sign_ins_refused_last_hour" => event_count(Masks::Server::Event::LOGIN_REFUSED, since),
          "masks_access_tokens_last_hour" => Masks::Server::AccessToken.where(created_at: since..).count
        }
      end

      def event_count(action, since)
        Masks::Server::Event.where(action: action, created_at: since..).count
      end

      def jobs
        return [] unless HealthController.jobs_run?

        [
          gauge("masks_jobs_failed_last_day", "Kinds of background job that failed in the last day.",
                [ [ nil, HealthController.failing_jobs.size ] ]),
          gauge("masks_jobs_waiting", "Background jobs ready to run and not yet picked up.",
                [ [ nil, SolidQueue::ReadyExecution.count ] ])
        ]
      end

      def gauge(name, help, samples)
        rows = samples.map do |tenant, value|
          labels = tenant ? %({tenant="#{tenant.to_s.gsub(/["\\\n]/, "_")}"}) : ""
          "#{name}#{labels} #{value}"
        end

        [ "# HELP #{name} #{help}", "# TYPE #{name} gauge", *rows ].join("\n")
      end
  end
end
