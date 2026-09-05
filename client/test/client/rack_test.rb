require_relative "test_helper"

class RackTest < ClientTest
  def app(**options)
    inner = ->(env) { [ 200, { "content-type" => "text/plain" }, [ env["masks.claims"]&.subject.to_s ] ] }

    Masks::Client::Rack.new(inner, resource: resource, **options)
  end

  def env(authorization: nil, path: "/mcp")
    { "PATH_INFO" => path, "HTTP_AUTHORIZATION" => authorization }.compact
  end

  def test_a_valid_token_reaches_the_app_as_claims
    status, _, body = app.call(env(authorization: "Bearer #{issuer.access_token}"))

    assert_equal 200, status
    assert_equal [ "actor-1" ], body
  end

  def test_a_missing_token_is_401_with_a_challenge
    status, headers, body = app.call(env)

    assert_equal 401, status
    assert_includes headers["www-authenticate"], "Bearer"
    assert_includes headers["www-authenticate"], "resource_metadata="
    assert_equal "no-store", headers["cache-control"]
    assert_equal "a bearer token is required", JSON.parse(body.first)["error_description"]
  end

  def test_an_insufficient_scope_is_403
    token = issuer.access_token(scope: "uris:read")

    status, headers, body = app(scope: "resources:command").call(env(authorization: "Bearer #{token}"))

    assert_equal 403, status
    assert_equal "insufficient_scope", JSON.parse(body.first)["error"]
    assert_includes headers["www-authenticate"], 'scope="resources:command"'
  end

  def test_only_skips_paths_it_does_not_guard
    guarded = app(only: ->(e) { e["PATH_INFO"] == "/mcp" })

    assert_equal 200, guarded.call(env(path: "/up")).first
    assert_equal 401, guarded.call(env(path: "/mcp")).first
  end

  def test_optional_lets_an_anonymous_request_through_and_records_why
    inner = ->(e) { [ 200, {}, [ e["masks.error"].class.name ] ] }
    guarded = Masks::Client::Rack.new(inner, resource: resource, optional: true)

    status, _, body = guarded.call(env)

    assert_equal 200, status
    assert_equal [ "Masks::Client::Unauthenticated" ], body
  end

  def test_optional_still_refuses_a_bad_token
    guarded = Masks::Client::Rack.new(->(_) { [ 200, {}, [] ] }, resource: resource, optional: true)

    assert_equal 401, guarded.call(env(authorization: "Bearer nonsense")).first
  end
end
