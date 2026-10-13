module Masks
  module Server
    require "test_helper"

    class BrowserAccessTest < ActionDispatch::IntegrationTest
      ORIGIN = "https://catalog.pages.dev".freeze

      setup { host! host_for(@tenant) }

      test "a page on another origin reads discovery and the keys" do
        %w[/.well-known/openid-configuration /.well-known/jwks.json].each do |path|
          get path, headers: { "Origin" => ORIGIN }

          assert_response :success
          assert_equal "*", response.headers["access-control-allow-origin"], path
        end
      end

      test "every endpoint discovery names for a page carries the grant" do
        get "/.well-known/openid-configuration"
        named = JSON.parse(response.body).values_at("jwks_uri", "token_endpoint", "revocation_endpoint",
                                                    "userinfo_endpoint", "avatar_endpoint")

        named.each do |url|
          process :options, "#{URI.parse(url).path}#{'/someone/identicon' if url.end_with?('/avatars')}",
                  headers: { "Origin" => ORIGIN, "Access-Control-Request-Method" => "GET" }

          assert_equal "*", response.headers["access-control-allow-origin"], url
        end
      end

      test "the token endpoint answers a preflight that names DPoP" do
        process :options, "/token", headers: {
          "Origin" => ORIGIN,
          "Access-Control-Request-Method" => "POST",
          "Access-Control-Request-Headers" => "dpop, content-type"
        }

        assert_response :no_content
        assert_equal "*", response.headers["access-control-allow-origin"]
        assert_includes response.headers["access-control-allow-headers"], "DPoP"
      end

      test "a refused token request can be read by the page, nonce included" do
        post "/token", params: { grant_type: "authorization_code", code: "nope" }, headers: { "Origin" => ORIGIN }

        assert_equal "*", response.headers["access-control-allow-origin"]
        assert_includes response.headers["access-control-expose-headers"], "DPoP-Nonce"
      end

      test "pages people sign in on, and requests with no origin, carry no grant" do
        get "/authorize", headers: { "Origin" => ORIGIN }
        assert_nil response.headers["access-control-allow-origin"]

        get "/.well-known/openid-configuration"
        assert_nil response.headers["access-control-allow-origin"]

        process :options, "/introspect", headers: { "Origin" => ORIGIN }
        assert_nil response.headers["access-control-allow-origin"]
      end
    end
  end
end
