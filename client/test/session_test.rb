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

  def test_introspection_answers_a_claims_object_rather_than_a_hash
    issuer.override("/introspect", {
                      "active" => true, "scope" => "things:read", "sub" => "actor-1",
                      "client_id" => "app", "username" => "owner", "token_type" => "Bearer",
                      "exp" => Time.now.to_i + 60, "aud" => [ "https://app.test/mcp" ]
                    })

    found = session.introspect("some-token", hint: "access_token")

    assert found.active?
    assert_equal "actor-1", found.subject
    assert_equal "owner", found.username
    assert_equal "Bearer", found.token_type
    assert_equal [ "things:read" ], found.scopes
    assert found.permits?("things:read")
    assert_equal "access_token", issuer.last("/introspect")[:body]["token_type_hint"]
  end

  def test_an_inactive_token_permits_nothing_however_wide_its_scope_reads
    issuer.override("/introspect", { "active" => false, "scope" => "things:read" })

    found = session.introspect("revoked")

    refute found.active?
    refute found.permits?("things:read")

    error = assert_raises(Masks::Client::Unauthorized) { found.permit!("things:read") }

    assert_match(/not active/, error.message)
  end

  def test_an_issuer_publishing_no_introspection_endpoint_is_refused_rather_than_guessed
    issuer.override("/.well-known/openid-configuration",
                    issuer.discovery.except("introspection_endpoint"))

    error = assert_raises(Masks::Client::Rejected) { session.introspect("whatever") }

    assert_match(/introspection_endpoint/, error.message)
  end
end
