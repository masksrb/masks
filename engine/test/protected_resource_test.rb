require "test_helper"

class ProtectedResourceTest < EngineIntegrationTest
  test "a call with no token is refused with somewhere to go and find one" do
    get "/catalog", headers: host

    assert_response :unauthorized

    challenge = response.headers["WWW-Authenticate"].to_s

    assert challenge.start_with?("Bearer")
    assert_includes challenge, "resource_metadata="
    assert_includes challenge, "catalog:read"
  end

  test "a refusal is never cacheable" do
    get "/catalog", headers: host

    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "a valid token is claims the controller can read" do
    get "/catalog", headers: host.merge("HTTP_AUTHORIZATION" => "Bearer #{token}")

    assert_response :success
    assert_equal "actor-1", json["subject"]
    assert_includes json["scopes"], "catalog:read"
  end

  test "a token that carries no such scope is refused as insufficient, not as unauthenticated" do
    get "/catalog", headers: host.merge(
      "HTTP_AUTHORIZATION" => "Bearer #{token(scopes: %w[catalog:write])}"
    )

    assert_response :forbidden
    assert_equal "insufficient_scope", json["error"]
    assert_includes response.headers["WWW-Authenticate"].to_s, "catalog:read"
  end

  test "a token minted for another audience is refused" do
    get "/catalog", headers: host.merge(
      "HTTP_AUTHORIZATION" => "Bearer #{token(audience: 'https://elsewhere.test/mcp')}"
    )

    assert_response :unauthorized
    assert_equal "invalid_token", json["error"]
  end

  test "a token minted by another tenant is refused, and fails on the key rather than the claim" do
    get "/catalog", headers: host.merge(
      "HTTP_AUTHORIZATION" => "Bearer #{token(subdomain: 'acme')}"
    )

    assert_response :unauthorized
  end

  test "an expired token is refused" do
    get "/catalog", headers: host.merge(
      "HTTP_AUTHORIZATION" => "Bearer #{token(expires_in: -60)}"
    )

    assert_response :unauthorized
  end

  test "a token that is not a token at all is refused rather than raising" do
    get "/catalog", headers: host.merge("HTTP_AUTHORIZATION" => "Bearer not-a-jwt")

    assert_response :unauthorized
    assert_equal "invalid_token", json["error"]
  end

  private

    def token(subdomain: SUBDOMAIN, scopes: %w[catalog:read], audience: nil, expires_in: 3600)
      issuer.mint(
        subdomain: subdomain,
        scopes: scopes,
        audience: audience || "#{origin}/mcp",
        expires_in: expires_in
      )
    end
end
