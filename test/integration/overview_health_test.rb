module Masks
  module Server
    require "test_helper"

    class OverviewHealthTest < ActionDispatch::IntegrationTest
      HEALTH = "{ health { name status summary details checkedAt changedAt } }".freeze
      RUN = "mutation { runHealthChecks { health { name status summary details } } }".freeze

      setup do
        host! host_for(@tenant)

        @console = create_client(
          @tenant,
          allowed_scopes: "openid profile email #{Scopes.join(ManageRoles::SCOPES)}",
          approved_at: Time.current,
          grant_types: [ "authorization_code", "refresh_token" ]
        )
      end

      def owner
        @owner ||= create_actor(@tenant, nickname: "owner", scopes: "openid profile email masks:manage")
      end

      def reader
        @reader ||= create_actor(@tenant, nickname: "reader", scopes: "openid profile email masks:manage:read")
      end

      def reader_bearer
        sign_in_as(reader)
        authorize(client_id: @console.client_id, scope: "openid masks:manage:read", resource: issuer_for(@tenant).manage_resource)
        consent! if awaiting_consent?

        token(grant_type: "authorization_code", code: code_from, redirect_uri: OidcFlow::REDIRECT_URI,
              code_verifier: verifier, client_id: @console.client_id)["access_token"]
      end

      def with_origin(origin)
        was = ::Rails.configuration.masks.public_origin_template
        ::Rails.configuration.masks.public_origin_template = origin

        yield
      ensure
        ::Rails.configuration.masks.public_origin_template = was
      end

      test "the overview has no checks before the first run, then every check once a manager checks now" do
        bearer = manage_bearer(owner, @console)
        before = manage(HEALTH, bearer: bearer)

        assert_nil before["errors"]
        assert_empty before.dig("data", "health")

        ran = manage(RUN, bearer: bearer)

        assert_nil ran["errors"]

        checks = ran.dig("data", "runHealthChecks", "health")

        assert_equal Health::NAMES.sort, checks.map { |check| check["name"] }
        assert_equal %w[ok], checks.map { |check| check["status"] }.uniq
        assert_equal "elsewhere", checks.find { |check| check["name"] == "jobs" }["summary"]
        assert_equal "manual", checks.find { |check| check["name"] == "keys" }["summary"]
        assert_equal 0, checks.find { |check| check["name"] == "keys" }.dig("details", "days")

        after = manage(HEALTH, bearer: bearer)

        assert_equal Health::NAMES.sort, after.dig("data", "health").map { |check| check["name"] }
        assert after.dig("data", "health").all? { |check| check["checkedAt"].present? && check["changedAt"].present? }
      end

      test "a reader sees the checks and cannot run them" do
        within { Health.store!([ Health.warning("keys", "stale", days: 40, period: 30) ]) }
        bearer = reader_bearer

        seen = manage(HEALTH, bearer: bearer)

        assert_nil seen["errors"], seen.inspect
        assert seen["data"], seen.inspect
        assert_equal [ [ "keys", "warning", "stale", { "days" => 40, "period" => 30 } ] ],
                     seen.dig("data", "health").map { |check| check.values_at("name", "status", "summary", "details") }

        refused = manage(RUN, bearer: bearer)

        assert_match(/needs/, refused["errors"].first["message"])
        assert_equal 1, within { HealthCheck.count }
      end

      test "a request that arrives at the wrong scheme is noted for the public address check" do
        Health.forget_origin!(@tenant)

        with_origin("https://%{subdomain}.auth.test") do
          get "/.well-known/openid-configuration"

          assert_response :ok
          assert_equal "https://#{host_for(@tenant)}", JSON.parse(response.body)["issuer"]

          found = within { Health.origin_result }

          assert_equal "warning", found.status
          assert_equal "mismatch", found.summary
          assert_equal "http://#{host_for(@tenant)}", found.details["seen"]
          assert_equal "https://#{host_for(@tenant)}", found.details["origin"]
        end
      ensure
        Health.forget_origin!(@tenant)
      end

      test "a request at the public address is not noted" do
        Health.forget_origin!(@tenant)

        with_origin("http://%{subdomain}.auth.test") do
          get "/.well-known/openid-configuration"

          assert_response :ok
          assert_equal "matches", within { Health.origin_result }.summary
        end
      end
    end
  end
end
