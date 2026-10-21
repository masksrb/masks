module Masks
  module Server
    require "test_helper"

    class HealthChecksTest < ActiveSupport::TestCase
      def stub(owner, name, value)
        held = owner.method(name)
        owner.define_singleton_method(name) { |*| value }

        yield
      ensure
        owner.define_singleton_method(name, held)
      end

      def queued(run: true, failing: [], heartbeat: 10.seconds.ago, oldest: nil, &block)
        stub(Queue, :run?, run) do
          stub(Queue, :failing_jobs, failing) do
            stub(Queue, :worker_heartbeat_at, heartbeat) { stub(Queue, :oldest_waiting_at, oldest, &block) }
          end
        end
      end

      def setting(name, value)
        settings = ::Rails.configuration.masks
        was = settings.public_send(name)
        settings.public_send("#{name}=", value)

        yield
      ensure
        settings.public_send("#{name}=", was)
      end

      def metrics_token(value)
        was = ENV["MASKS_METRICS_TOKEN"]
        ENV["MASKS_METRICS_TOKEN"] = value

        yield
      ensure
        ENV["MASKS_METRICS_TOKEN"] = was
      end

      def result(name, &block)
        within { Health.public_send("#{name}_result") }
      end

      def smtp_sender
        within do
          Senders::Smtp.new(key: "relay", name: "Relay", primary: true)
                       .configure(from: "masks@example.invalid", address: "smtp.example.invalid", port: 2525, tls: true)
                       .tap(&:save!)
        end
      end

      test "jobs is fine with no failures and failing with the kinds that failed" do
        queued { assert_equal [ "ok", "none" ], result(:jobs).then { |r| [ r.status, r.summary ] } }

        queued(failing: %w[Masks::Server::CleanupJob Masks::Server::IdleAccountsJob]) do
          found = result(:jobs)

          assert_equal "failing", found.status
          assert_equal "failed", found.summary
          assert_equal 2, found.details["count"]
          assert_equal %w[CleanupJob IdleAccountsJob], found.details["jobs"]
        end
      end

      test "jobs, worker, and queue say jobs run elsewhere when this server runs none" do
        queued(run: false) do
          assert_equal %w[elsewhere elsewhere elsewhere], [ result(:jobs), result(:worker), result(:queue) ].map(&:summary)
          assert [ result(:jobs), result(:worker), result(:queue) ].none?(&:failing?)
        end
      end

      test "worker is failing when no worker has reported, and unchecked when the silence is zero" do
        queued(heartbeat: nil) do
          found = result(:worker)

          assert_equal "failing", found.status
          assert_equal "silent", found.summary
          assert_equal 5, found.details["minutes"]
        end

        queued(heartbeat: 6.minutes.ago) { assert_equal "silent", result(:worker).summary }
        queued { assert_equal "reporting", result(:worker).summary }
        queued(heartbeat: nil) { setting(:worker_silence, 0.seconds) { assert_equal "unchecked", result(:worker).summary } }
      end

      test "queue is failing when a job waited past the limit" do
        waited = 11.minutes.ago

        queued(oldest: waited) do
          found = result(:queue)

          assert_equal "failing", found.status
          assert_equal "stuck", found.summary
          assert_equal waited.utc.iso8601, found.details["since"]
          assert_equal 10, found.details["minutes"]
        end

        queued(oldest: 1.minute.ago) { assert_equal "moving", result(:queue).summary }
        queued(oldest: 11.minutes.ago) { setting(:queue_wait, 0.seconds) { assert_equal "unchecked", result(:queue).summary } }
      end

      test "ldap is local without a certificate, tls with one, and a warning in plaintext" do
        setting(:ldap_cert, nil) do
          setting(:ldap_plaintext, false) { assert_equal [ "ok", "local" ], result(:ldap).then { |r| [ r.status, r.summary ] } }

          setting(:ldap_plaintext, true) do
            found = result(:ldap)

            assert_equal "warning", found.status
            assert_equal "plain", found.summary
            assert_equal ::Rails.configuration.masks.ldap_port, found.details["port"]
          end
        end

        setting(:ldap_cert, "/certs/ldap.pem") { assert_equal "tls", result(:ldap).summary }
      end

      test "metrics is off without a token, a warning with a short one, and on with a long one" do
        metrics_token(nil) { assert_equal [ "ok", "off" ], result(:metrics).then { |r| [ r.status, r.summary ] } }

        metrics_token("short") do
          found = result(:metrics)

          assert_equal "warning", found.status
          assert_equal "short", found.summary
          assert_equal 5, found.details["length"]
          assert_equal 24, found.details["needed"]
        end

        metrics_token(SecureRandom.hex(16)) { assert_equal [ "ok", "on" ], result(:metrics).then { |r| [ r.status, r.summary ] } }
      end

      test "mail is none without a mail server, answers when it does, and failing with the error's class" do
        setting(:smtp_settings, nil) { assert_equal [ "ok", "none" ], result(:mail).then { |r| [ r.status, r.summary ] } }

        probed = nil

        stub(Health, :smtp_problem, nil) do
          Health.define_singleton_method(:smtp_problem) { |settings| probed = settings; nil }
          smtp_sender

          assert_equal [ "ok", "answers" ], result(:mail).then { |r| [ r.status, r.summary ] }
          assert_equal({ address: "smtp.example.invalid", port: 2525, tls: true, domain: nil }, probed)
        end

        stub(Health, :smtp_problem, "Net::OpenTimeout") do
          found = result(:mail)

          assert_equal "failing", found.status
          assert_equal "silent", found.summary
          assert_equal "Net::OpenTimeout", found.details["error"]
        end
      end

      test "a tenant's mail server that now resolves to a private address is never probed" do
        smtp_sender
        probed = false

        stub(Health, :smtp_problem, nil) do
          Health.define_singleton_method(:smtp_problem) { |*| probed = true; nil }

          found = deployed { resolving("10.0.0.5") { result(:mail) } }

          assert_equal "failing", found.status
          assert_equal Senders::Smtp::UNREACHABLE, found.details["error"]
        end

        assert_not probed
      end

      test "the server's own mail settings are probed when the tenant has no sender" do
        probed = nil

        setting(:smtp_settings, { address: "relay.example.invalid", port: 587, tls: false, enable_starttls: true }) do
          stub(Health, :smtp_problem, nil) do
            Health.define_singleton_method(:smtp_problem) { |settings| probed = settings; nil }

            assert_equal "answers", result(:mail).summary
          end
        end

        assert_equal({ address: "relay.example.invalid", port: 587, tls: false, domain: nil }, probed)
      end

      test "a probe that cannot connect names the error and sends no mail" do
        settings = { address: "127.0.0.1", port: 1, tls: false, domain: nil }

        assert_includes [ "Errno::ECONNREFUSED", "Errno::EADDRNOTAVAIL", "Net::OpenTimeout" ], Health.smtp_problem(settings)
      end

      test "origin is unset without a template, matches with one, and a mismatch once a request arrived elsewhere" do
        setting(:public_origin_template, nil) { assert_equal "unset", result(:origin).summary }

        setting(:public_origin_template, "https://%{subdomain}.auth.test") do
          Health.forget_origin!(@tenant)

          assert_equal [ "ok", "matches" ], result(:origin).then { |r| [ r.status, r.summary ] }

          Health.note_origin!(@tenant, "http://#{@tenant.subdomain}.auth.test", "https://#{@tenant.subdomain}.auth.test")
          found = result(:origin)

          assert_equal "warning", found.status
          assert_equal "mismatch", found.summary
          assert_equal "http://#{@tenant.subdomain}.auth.test", found.details["seen"]
          assert_equal "https://#{@tenant.subdomain}.auth.test", found.details["origin"]

          Health.forget_origin!(@tenant)

          assert_equal "matches", result(:origin).summary
        end
      end

      test "a request at the public address is not noted, and a second note within ten minutes is not written" do
        Health.forget_origin!(@tenant)
        Health.note_origin!(@tenant, "https://demo.auth.test", "https://demo.auth.test")
        Health.note_origin!(@tenant, "HTTPS://demo.auth.test", "https://demo.auth.test")

        assert_nil ::Rails.cache.read(Health.origin_key(@tenant))

        Health.note_origin!(@tenant, "http://demo.auth.test", "https://demo.auth.test")
        Health.note_origin!(@tenant, "http://demo.auth.test:8080", "https://demo.auth.test")

        assert_equal "http://demo.auth.test", ::Rails.cache.read(Health.origin_key(@tenant))["seen"]
      ensure
        Health.forget_origin!(@tenant)
      end

      test "domains is none, proven, or missing with the domains named" do
        assert_equal [ "ok", "none" ], result(:domains).then { |r| [ r.status, r.summary ] }

        claim = within { DomainClaim.create!(domain: "acme.example").tap { |held| held.update_columns(verified_at: Time.current) } }

        assert_equal "proven", result(:domains).summary

        within { claim.update_columns(missing_since: 1.hour.ago) }
        found = result(:domains)

        assert_equal "warning", found.status
        assert_equal "missing", found.summary
        assert_equal [ "acme.example" ], found.details["domains"]
      end

      test "keys is manual, fresh, stale, or missing" do
        found = result(:keys)

        assert_equal [ "ok", "manual" ], [ found.status, found.summary ]
        assert_equal 0, found.details["days"]

        @tenant.update!(key_rotation_days: 30)

        travel(10.days + 1.hour) do
          found = result(:keys)

          assert_equal [ "ok", "fresh" ], [ found.status, found.summary ]
          assert_equal({ "days" => 10, "period" => 30 }, found.details)
        end

        travel(31.days + 1.hour) do
          found = result(:keys)

          assert_equal [ "warning", "stale" ], [ found.status, found.summary ]
          assert_equal 31, found.details["days"]
        end

        within { SigningKey.update_all(retired_at: 1.minute.ago) }

        assert_equal [ "failing", "missing" ], result(:keys).then { |r| [ r.status, r.summary ] }
      end

      def events(action)
        within { Event.where(action: action).order(:id).to_a }
      end

      test "storing a result records health.failing once, then health.recovered when it is fine again" do
        failing = Health.failing("mail", "silent", error: "Net::OpenTimeout")
        warning = Health.warning("mail", "silent", error: "Net::OpenTimeout")
        fine = Health.ok("mail", "answers")

        rows = within { Health.store!([ failing ]) }

        assert_equal 1, rows.size
        assert_equal "failing", rows.first.status
        assert_equal rows.first.checked_at, rows.first.changed_at

        travel(1.minute) { within { Health.store!([ failing ]) } }

        assert_equal 1, events(Event::HEALTH_FAILING).size
        assert_equal({ "check" => "mail", "summary" => "silent" }, events(Event::HEALTH_FAILING).first.details)
        assert_equal 1, within { HealthCheck.count }

        travel(2.minutes) { within { Health.store!([ warning ]) } }

        assert_empty events(Event::HEALTH_RECOVERED)
        assert_equal "warning", within { HealthCheck.find_by!(name: "mail").status }

        travel(3.minutes) { within { Health.store!([ fine ]) } }

        assert_empty events(Event::HEALTH_RECOVERED), "recovering from a warning is not announced"

        travel(4.minutes) { within { Health.store!([ failing ]) } }
        travel(5.minutes) { within { Health.store!([ fine ]) } }

        assert_equal 2, events(Event::HEALTH_FAILING).size
        assert_equal 1, events(Event::HEALTH_RECOVERED).size

        row = within { HealthCheck.find_by!(name: "mail") }

        assert_equal "ok", row.status
        assert_operator row.changed_at, :>, row.created_at
      end

      test "health.failing is grave and the labels are translated" do
        assert_includes Event::GRAVE, Event::HEALTH_FAILING
        assert_not_includes Event::GRAVE, Event::HEALTH_RECOVERED
        assert_equal "Health check failing", I18n.t("events.actions.health.failing")
      end

      test "checking a tenant stores every check and remembers the failing ones for /up" do
        rows = queued(failing: %w[Masks::Server::CleanupJob]) do
          stub(Health, :smtp_problem, "Net::OpenTimeout") do
            smtp_sender
            within { Health.check! }
          end
        end

        assert_equal Health::NAMES.sort, rows.map(&:name).sort
        assert_equal %w[jobs mail], rows.select(&:failing?).map(&:name).sort
        assert_equal [ "jobs", "mail (#{@tenant.subdomain})" ], Health.failing_named
      end

      test "remembering a tenant's results replaces its earlier entries and leaves other tenants' alone" do
        Health.remember_all!({ "mail" => [ "acme", @tenant.subdomain ], "keys" => [ @tenant.subdomain ] })

        within { Health.remember!(@tenant, [ HealthCheck.new(name: "domains", status: "failing") ]) }

        assert_equal [ "domains (#{@tenant.subdomain})", "mail (acme)" ], Health.failing_named

        within { Health.remember!(@tenant, []) }

        assert_equal [ "mail (acme)" ], Health.failing_named
      end
    end
  end
end
