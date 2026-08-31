require_relative "test_helper"

class SessionTest < ClientTest
  def session
    Masks::Client::Session.new(
      issuer: issuer.url, client_id: "app",
      redirect_uri: "https://app.test/callback", scope: %w[openid things:read]
    )
  end

  def test_the_authorization_url_carries_pkce_and_every_resource
    started = session.start(resource: [ "https://app.test/mcp", "https://app.test/api" ])
    query = URI.decode_www_form(URI.parse(started[:url]).query)

    assert_equal "code", query.assoc("response_type").last
    assert_equal "S256", query.assoc("code_challenge_method").last
    assert_equal [ "https://app.test/mcp", "https://app.test/api" ],
                 query.select { |name, _| name == "resource" }.map(&:last)
    refute_includes started[:url], started[:verifier]
  end

  def test_a_nonce_travels_only_when_an_id_token_was_asked_for
    started = session.start
    query = URI.decode_www_form(URI.parse(started[:url]).query)

    assert_equal started[:nonce], query.assoc("nonce").last
    refute_nil started[:nonce]

    started = session.start(scope: %w[things:read])
    query = URI.decode_www_form(URI.parse(started[:url]).query)

    assert_nil started[:nonce]
    assert_nil query.assoc("nonce")
  end

  def test_a_token_response_without_an_access_token_is_refused
    issuer.override("/token", { "token_type" => "Bearer", "expires_in" => 3600 })

    error = assert_raises(Masks::Client::Rejected) do
      session.complete(code: "abc", verifier: "v")
    end

    assert_equal "invalid_token_response", error.code
  end

  def test_an_error_body_answered_with_200_is_still_refused
    issuer.override("/token", { "error" => "invalid_grant",
                                "error_description" => "that code expired" })

    error = assert_raises(Masks::Client::Rejected) { session.complete(code: "abc", verifier: "v") }

    assert_equal "invalid_grant", error.code
    assert_equal "that code expired", error.description
  end

  def test_a_granted_response_becomes_tokens
    issuer.override("/token", { "access_token" => "at", "token_type" => "Bearer",
                                "scope" => "openid things:read", "expires_in" => 3600 })

    tokens = session.complete(code: "abc", verifier: "v")

    assert_equal "at", tokens.access_token
    assert_equal %w[openid things:read], tokens.scopes
    assert_equal "Bearer at", tokens.authorization
    refute tokens.expired?
  end
end
