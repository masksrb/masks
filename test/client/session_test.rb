require_relative "test_helper"

class SessionTest < ClientTest
  def session
    Masks::Client::Session.new(
      issuer: issuer.url, client_id: "app",
      redirect_uri: "https://app.test/callback", scope: %w[openid uris:catalog:read]
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

    started = session.start(scope: %w[uris:catalog:read])
    query = URI.decode_www_form(URI.parse(started[:url]).query)

    assert_nil started[:nonce]
    assert_nil query.assoc("nonce")
  end

  def test_a_service_asks_for_its_own_token_with_a_secret
    issuer.override("/token", { "access_token" => "at", "token_type" => "Bearer", "scope" => "uris:catalog:read", "expires_in" => 60 })

    service = Masks::Client::Session.new(issuer: issuer.url, client_id: "indexer", client_secret: "shh")
    tokens = service.client_credentials(scope: "uris:catalog:read", resource: "https://app.test/mcp")
    sent = issuer.last("/token")

    assert_equal "at", tokens.access_token
    assert_equal "client_credentials", sent[:body]["grant_type"]
    assert_equal "https://app.test/mcp", sent[:body]["resource"]
    assert_equal "Basic #{Base64.strict_encode64('indexer:shh')}", sent[:headers]["authorization"]
  end

  def test_a_client_holding_a_private_key_signs_an_assertion_instead_of_sending_a_secret
    issuer.override("/token", { "access_token" => "at", "token_type" => "Bearer", "expires_in" => 60 })
    key = OpenSSL::PKey::EC.generate("prime256v1")

    service = Masks::Client::Session.new(issuer: issuer.url, client_id: "indexer", private_key: key.to_pem, key_id: "k-1")
    service.client_credentials
    service.client_credentials

    sent = issuer.last("/token")
    claims, header = JWT.decode(sent[:body]["client_assertion"], key, true, algorithms: [ "ES256" ])

    assert_nil sent[:headers]["authorization"]
    assert_equal Masks::Client::Session::ASSERTION_TYPE, sent[:body]["client_assertion_type"]
    assert_equal "k-1", header["kid"]
    assert_equal [ "indexer", "indexer", issuer.url ], claims.values_at("iss", "sub", "aud")
    assert_operator claims["exp"], :<=, Time.now.to_i + 60
  end

  def test_a_secret_and_a_private_key_together_are_refused
    assert_raises(ArgumentError) do
      Masks::Client::Session.new(issuer: issuer.url, client_id: "x", client_secret: "s",
                                 private_key: OpenSSL::PKey::EC.generate("prime256v1"))
    end
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
                                "scope" => "openid uris:catalog:read", "expires_in" => 3600 })

    tokens = session.complete(code: "abc", verifier: "v")

    assert_equal "at", tokens.access_token
    assert_equal %w[openid uris:catalog:read], tokens.scopes
    assert_equal "Bearer at", tokens.authorization
    refute tokens.expired?
  end

  def test_introspection_answers_a_claims_object_rather_than_a_hash
    issuer.override("/introspect", {
                      "active" => true, "scope" => "uris:catalog:read", "sub" => "actor-1",
                      "client_id" => "app", "username" => "owner", "token_type" => "Bearer",
                      "exp" => Time.now.to_i + 60, "aud" => [ "https://app.test/mcp" ]
                    })

    found = session.introspect("some-token", hint: "access_token")

    assert found.active?
    assert_equal "actor-1", found.subject
    assert_equal "owner", found.nickname
    assert_equal "Bearer", found.token_type
    assert_equal [ "uris:catalog:read" ], found.scopes
    assert found.permits?("uris:catalog:read")
    assert_equal "access_token", issuer.last("/introspect")[:body]["token_type_hint"]
  end

  def test_an_inactive_token_permits_nothing_however_wide_its_scope_reads
    issuer.override("/introspect", { "active" => false, "scope" => "uris:catalog:read" })

    found = session.introspect("revoked")

    refute found.active?
    refute found.permits?("uris:catalog:read")

    error = assert_raises(Masks::Client::Unauthorized) { found.permit!("uris:catalog:read") }

    assert_match(/not active/, error.message)
  end

  def test_an_issuer_publishing_no_introspection_endpoint_is_refused_rather_than_guessed
    issuer.override("/.well-known/openid-configuration",
                    issuer.discovery.except("introspection_endpoint"))

    error = assert_raises(Masks::Client::Rejected) { session.introspect("whatever") }

    assert_match(/introspection_endpoint/, error.message)
  end
end
