module Masks
  module Server
    require "test_helper"

    class PinnedOriginTest < ActionDispatch::IntegrationTest
      def pinning(pin: true, &)
        with_masks_config(pin_origin: pin, tenant: @tenant.subdomain, &)
      end

      def with_origin(origin, &)
        with_masks_config(public_origin_template: origin, &)
      end

      def discovery
        get "/.well-known/openid-configuration"

        JSON.parse(response.body)
      end

      test "before setup, the issuer follows the address the server is opened at" do
        pinning do
          host! "first.example.test"
          assert_equal "http://first.example.test", discovery["issuer"]

          host! "second.example.test"
          assert_equal "http://second.example.test", discovery["issuer"]
        end
      end

      test "setup keeps the address it was opened at as the issuer" do
        pinning do
          host! "auth.example.test"

          assert set_up!["settled"]
          assert_equal "http://auth.example.test", @tenant.reload.pinned_origin
          assert_equal "http://auth.example.test", @tenant.public_origin
          assert_equal "http://auth.example.test", discovery["issuer"]
        end
      end

      test "after setup, another address is refused and told where masks answers" do
        pinning do
          host! "auth.example.test"
          set_up!

          host! "attacker.example.test"
          get "/.well-known/openid-configuration"

          assert_response :not_found
          assert_match "masks answers at http://auth.example.test", response.body
          assert_match "MASKS_PUBLIC_ORIGIN_TEMPLATE", response.body

          post "/login", params: { event: "identify", identifier: "owner" }, as: :json

          assert_response :not_found
        end
      end

      test "after setup, the same host on another port is refused" do
        pinning do
          host! "auth.example.test"
          set_up!

          host! "auth.example.test:8080"
          get "/.well-known/openid-configuration"

          assert_response :not_found
        end
      end

      test "an origin template moves a server whose address was kept" do
        pinning do
          host! "auth.example.test"
          set_up!

          with_origin("https://id.example.test") do
            host! "id.example.test"

            assert_equal "https://id.example.test", discovery["issuer"]
            assert_equal "https://id.example.test", @tenant.reload.public_origin
          end
        end
      end

      test "a tenant set up without a kept address is refused until a template names one" do
        create_actor(@tenant, nickname: "owner", password: "a-long-enough-password")

        pinning do
          host! "attacker.example.test"
          get "/.well-known/openid-configuration"

          assert_response :not_found
          assert_match "set up without a kept address", response.body

          with_origin("https://auth.example.test") do
            host! "auth.example.test"

            assert_equal "https://auth.example.test", discovery["issuer"]
          end
        end
      end

      test "with pinning off, setup keeps no address and the issuer follows the host" do
        pinning(pin: false) do
          host! "auth.example.test"
          set_up!

          assert_nil @tenant.reload.pinned_origin

          host! "elsewhere.example.test"
          assert_equal "http://elsewhere.example.test", discovery["issuer"]
        end
      end

      test "with an origin template, setup keeps no address" do
        pinning do
          with_origin("http://%{subdomain}.auth.test") do
            host! host_for(@tenant)
            set_up!

            assert_nil @tenant.reload.pinned_origin
          end
        end
      end
    end
  end
end
