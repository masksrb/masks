require "net/smtp"

module Masks
  module Server
    module Health
      Result = Struct.new(:name, :status, :summary, :details) do
        def failing?
          status == HealthCheck::FAILING
        end
      end

      SERVER = %w[jobs worker queue ldap metrics].freeze
      TENANT = %w[mail origin domains keys].freeze
      NAMES = (SERVER + TENANT).freeze

      FAILING_KEY = "masks:health:failing".freeze
      ORIGIN_PREFIX = "masks:health:origin:".freeze
      KEEP = 1.day
      NOTE_EVERY = 10.minutes
      SMTP_TIMEOUT = 5
      TOKEN_LENGTH = 24

      SMTP_ERRORS = [
        Net::SMTPError, IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError
      ].freeze

      module_function

      def check!(tenant = Current.tenant)
        rows = store!(server_results + tenant_results)
        remember!(tenant, rows)
        rows
      end

      def server_results
        [ jobs_result, worker_result, queue_result, ldap_result, metrics_result ]
      end

      def tenant_results
        [ mail_result, origin_result, domains_result, keys_result ]
      end

      def store!(results)
        now = Time.current

        results.map do |result|
          row = HealthCheck.find_or_initialize_by(name: result.name)
          was = row.status

          row.assign_attributes(status: result.status, summary: result.summary, details: result.details, checked_at: now)
          row.changed_at = now if was != result.status
          row.save!

          announce(row, was)

          row
        end
      end

      def announce(row, was)
        if row.failing? && was != HealthCheck::FAILING
          Event.record!(Event::HEALTH_FAILING, by: nil, check: row.name, summary: row.summary)
        elsif row.ok? && was == HealthCheck::FAILING
          Event.record!(Event::HEALTH_RECOVERED, by: nil, check: row.name, summary: row.summary)
        end
      end

      def remember!(tenant, rows)
        held = (::Rails.cache.read(FAILING_KEY) || {}).transform_values { |subdomains| subdomains - [ tenant.subdomain ] }
        rows.select(&:failing?).each { |row| (held[row.name] ||= []) << tenant.subdomain }

        remember_all!(held)
      end

      def remember_all!(failing)
        ::Rails.cache.write(FAILING_KEY, failing.reject { |_, subdomains| subdomains.empty? }, expires_in: KEEP)
      end

      def failing_named
        (::Rails.cache.read(FAILING_KEY) || {}).sort.map do |name, subdomains|
          SERVER.include?(name) ? name : "#{name} (#{subdomains.sort.join(', ')})"
        end
      end

      def jobs_result
        return ok("jobs", "elsewhere") unless Queue.run?

        failed = Queue.failing_jobs

        return ok("jobs", "none") if failed.empty?

        failing("jobs", "failed", count: failed.size, jobs: failed.map(&:demodulize))
      end

      def worker_result
        return ok("worker", "elsewhere") unless Queue.run?
        return ok("worker", "unchecked") unless Queue.silence.positive?
        return failing("worker", "silent", minutes: Queue.silence.to_i / 60) if Queue.worker_silent?

        ok("worker", "reporting")
      end

      def queue_result
        return ok("queue", "elsewhere") unless Queue.run?
        return ok("queue", "unchecked") unless Queue.wait.positive?

        stuck = Queue.stuck_since

        return failing("queue", "stuck", since: stuck.utc.iso8601, minutes: Queue.wait.to_i / 60) if stuck

        ok("queue", "moving")
      end

      def ldap_result
        settings = ::Rails.configuration.masks

        return ok("ldap", "tls") if settings.ldap_cert.present?
        return ok("ldap", "local") unless settings.ldap_plaintext

        warning("ldap", "plain", port: settings.ldap_port)
      end

      def metrics_result
        token = ENV["MASKS_METRICS_TOKEN"]

        return ok("metrics", "off") if token.blank?
        return warning("metrics", "short", length: token.length, needed: TOKEN_LENGTH) if token.length < TOKEN_LENGTH

        ok("metrics", "on")
      end

      def mail_result
        settings = smtp_settings

        return ok("mail", "none") if settings.nil?

        return failing("mail", "silent", error: Senders::Smtp::UNREACHABLE) if settings.delete(:vetted) && !public_smtp?(settings)

        error = smtp_problem(settings)

        error ? failing("mail", "silent", error: error) : ok("mail", "answers")
      end

      def smtp_settings
        sender = Sender.primary(Sender::MAIL)

        if sender.is_a?(Senders::Smtp)
          { address: sender[:address], port: sender[:port].to_i, tls: sender[:tls] == true, domain: sender[:domain], vetted: true }
        elsif (held = ::Rails.configuration.masks.smtp_settings)
          { address: held[:address], port: held[:port].to_i, tls: held[:tls] == true, domain: held[:domain] }
        end
      end

      def public_smtp?(settings)
        ::Rails.env.local? || Outbound.public_address(settings[:address], settings[:port]).present?
      end

      def smtp_problem(settings)
        smtp = Net::SMTP.new(settings[:address], settings[:port])
        smtp.open_timeout = SMTP_TIMEOUT
        smtp.read_timeout = SMTP_TIMEOUT
        settings[:tls] ? smtp.enable_tls : smtp.enable_starttls_auto

        smtp.start(settings[:domain].presence || "localhost") { nil }

        nil
      rescue *SMTP_ERRORS => error
        error.class.name
      end

      def origin_result
        return ok("origin", "unset") if Current.tenant&.public_origin.nil?

        noted = ::Rails.cache.read(origin_key(Current.tenant))

        return ok("origin", "matches") if noted.nil?

        warning("origin", "mismatch", seen: noted["seen"], origin: noted["origin"])
      end

      def note_origin!(tenant, seen, origin)
        return if seen.nil? || origin.nil? || seen.casecmp?(origin)

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        last = noted[tenant.id]

        return if last && now - last < NOTE_EVERY

        noted[tenant.id] = now
        ::Rails.cache.write(origin_key(tenant), { "seen" => seen, "origin" => origin }, expires_in: KEEP)
      end

      def forget_origin!(tenant)
        noted.delete(tenant.id)
        ::Rails.cache.delete(origin_key(tenant))
      end

      def noted
        @noted ||= Concurrent::Map.new
      end

      def origin_key(tenant)
        "#{ORIGIN_PREFIX}#{tenant.id}"
      end

      def domains_result
        return ok("domains", "none") unless DomainClaim.exists?

        missing = DomainClaim.where.not(missing_since: nil).order(:domain).pluck(:domain)

        return ok("domains", "proven") if missing.empty?

        warning("domains", "missing", domains: missing)
      end

      def keys_result
        active = SigningKey.active.first

        return failing("keys", "missing") if active.nil?

        days = ((Time.current - active.activated_at) / 1.day).floor
        period = Current.tenant.key_rotation_days

        return ok("keys", "manual", days: days) if period.nil?
        return warning("keys", "stale", days: days, period: period) if days > period

        ok("keys", "fresh", days: days, period: period)
      end

      def ok(name, summary, **details)
        Result.new(name, HealthCheck::OK, summary, details.stringify_keys)
      end

      def warning(name, summary, **details)
        Result.new(name, HealthCheck::WARNING, summary, details.stringify_keys)
      end

      def failing(name, summary, **details)
        Result.new(name, HealthCheck::FAILING, summary, details.stringify_keys)
      end
    end
  end
end
