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

      test "metrics answer on a host no tenant serves" do
        host! "unserved.example.net"

        get "/metrics", headers: { "HTTP_AUTHORIZATION" => "Bearer a-long-metrics-token" }

        assert_response :ok
      end
    end
  end
end
