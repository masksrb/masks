module Masks
  module Server
    require "test_helper"

    class MetricsTest < ActionDispatch::IntegrationTest
      setup do
        @held = ENV["MASKS_METRICS_TOKEN"]
        ENV["MASKS_METRICS_TOKEN"] = "a-long-metrics-token"
        host! host_for(@tenant)
        create_actor(nickname: "ada")
      end

      teardown { @held ? ENV["MASKS_METRICS_TOKEN"] = @held : ENV.delete("MASKS_METRICS_TOKEN") }

      test "Prometheus reads each tenant's counts with the token" do
        get "/metrics", headers: { "HTTP_AUTHORIZATION" => "Bearer a-long-metrics-token" }

        assert_response :ok
        assert_match %(masks_actors{tenant="#{@tenant.subdomain}"} 1), response.body
        assert_match "# TYPE masks_sign_ins_last_hour gauge", response.body
      end

      test "the token is required, and only as a bearer token" do
        get "/metrics"
        assert_response :unauthorized

        get "/metrics", headers: { "HTTP_AUTHORIZATION" => "a-long-metrics-token" }
        assert_response :unauthorized
      end

      test "without the variable there is no endpoint" do
        ENV.delete("MASKS_METRICS_TOKEN")

        get "/metrics", headers: { "HTTP_AUTHORIZATION" => "Bearer " }

        assert_response :not_found
      end

      test "each route's answers are timed into a histogram and counted by status" do
        before = scraped

        get "/.well-known/openid-configuration"
        get "/.well-known/jwks.json"
        get "/login"
        get "/.well-known/openid-configuration", headers: { "HTTP_ACCEPT" => "text/html" }

        after = scraped

        assert_equal 3, after.count("discovery") - before.count("discovery")
        assert_equal 1, after.count("login") - before.count("login")
        assert_equal 3, after.bucket("discovery", "+Inf") - before.bucket("discovery", "+Inf")
        assert_operator after.sum("discovery"), :>, before.sum("discovery")
        assert_equal 3, after.total("discovery", "2xx") - before.total("discovery", "2xx")
        assert_match "# TYPE masks_request_seconds histogram", after.body
        assert_match "# TYPE masks_requests_total counter", after.body
        assert_match %(masks_request_seconds_bucket{route="token",le="0.005"} ), after.body
      end

      test "scrapes and health checks are not counted" do
        before = scraped

        get "/up"
        get "/metrics", headers: { "HTTP_AUTHORIZATION" => "Bearer a-long-metrics-token" }

        assert_equal 0, scraped.count("other") - before.count("other")
      end

      test "metrics answer on a host no tenant serves" do
        host! "unserved.example.net"

        get "/metrics", headers: { "HTTP_AUTHORIZATION" => "Bearer a-long-metrics-token" }

        assert_response :ok
      end

      private

        Scrape = Struct.new(:body) do
          def count(route) = value(%(masks_request_seconds_count{route="#{route}"}))
          def sum(route) = value(%(masks_request_seconds_sum{route="#{route}"}))
          def bucket(route, bound) = value(%(masks_request_seconds_bucket{route="#{route}",le="#{bound}"}))
          def total(route, status) = value(%(masks_requests_total{route="#{route}",status="#{status}"}))

          def value(series)
            line = body.lines.find { |held| held.start_with?("#{series} ") }

            line ? line.split(" ").last.to_f : 0
          end
        end

        def scraped
          get "/metrics", headers: { "HTTP_AUTHORIZATION" => "Bearer a-long-metrics-token" }

          assert_response :ok

          Scrape.new(response.body)
        end
    end
  end
end
