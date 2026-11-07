require_relative "test_helper"

class FakeTest < ClientTest
  def setup
    super
    issuer.add("app", method: "client_secret_basic", secret: "s3cret")
  end

  def session(**options)
    Masks::Client::Session.new(
      issuer: issuer.url, client_id: "app", client_secret: "s3cret",
      redirect_uri: "https://app.test/callback", scope: %w[openid profile email offline_access organization], **options
    )
  end

  def returned(url)
    URI.decode_www_form(URI.parse(url).query).to_h
  end

  def test_a_sign_in_completes_against_the_fake
    app = session
    started = app.start(organization: "acme", resource: "https://app.test/mcp")
    answer = returned(issuer.authorize(started[:url]))

    assert_equal started[:state], answer["state"]
    assert_equal issuer.url, answer["iss"]

    tokens = app.complete(code: answer["code"], verifier: started[:verifier])
    identity = app.identity(tokens, nonce: started[:nonce])

    assert_equal "ada", identity["sub"]
    assert_equal "Ada Lovelace", identity["name"]
    assert_equal "acme", identity["org"]["key"]
    assert_equal "openid profile email offline_access organization", tokens.scope
    refute_nil tokens.refresh_token

    claims = Masks::Client.verifier(issuer.url, audience: "https://app.test/mcp").verify(tokens.access_token, typ: Masks::Client::Verifier::ACCESS_TOKEN)

    assert_equal "ada", claims["sub"]
    assert_equal "app", claims["client_id"]
  end

  def test_a_sign_in_the_person_declines_comes_back_as_an_error
    answer = returned(issuer.authorize(session.start[:url], error: "access_denied"))

    assert_equal "access_denied", answer["error"]
    assert_nil answer["code"]
  end

  def test_a_refresh_against_the_fake_rotates_the_token
    app = session
    started = app.start
    tokens = app.complete(code: returned(issuer.authorize(started[:url]))["code"], verifier: started[:verifier])
    renewed = app.refresh(tokens.refresh_token)

    refute_equal tokens.refresh_token, renewed.refresh_token
    refute_equal tokens.access_token, renewed.access_token
    assert_equal "ada", app.identity(renewed)["sub"]

    error = assert_raises(Masks::Client::Refused) { app.refresh(tokens.refresh_token) }

    assert_equal "invalid_grant", error.code
  end

  def test_a_logout_token_from_the_fake_verifies
    logout = session.logout_token(issuer.logout_token("app", subject: "ada", sid: "sid-1"))

    assert_equal "ada", logout.subject
    assert_equal "sid-1", logout.sid

    assert_raises(Masks::Client::InvalidToken) { session.logout_token(issuer.logout_token("other")) }
  end

  def test_a_bound_sign_in_carries_the_key_through_the_fake
    key = Masks::Client::Key.generate
    app = session(dpop: key)
    started = app.start
    tokens = app.complete(code: returned(issuer.authorize(started[:url]))["code"], verifier: started[:verifier])

    assert tokens.bound?
    assert_equal key.thumbprint, JWT.decode(tokens.access_token, nil, false).first.dig("cnf", "jkt")
    assert_equal "ada", app.userinfo(tokens)["sub"]
  end

  def test_a_service_signs_in_with_its_own_credentials
    issuer.add("indexer", method: "client_secret_basic", secret: "shh", scope: "xixo:catalog:read")
    service = Masks::Client::Session.new(issuer: issuer.url, client_id: "indexer", client_secret: "shh")
    tokens = service.client_credentials

    assert_equal "xixo:catalog:read", tokens.scope
    assert_equal "client_credentials", issuer.last("/token")[:body]["grant_type"]
    assert service.introspect(tokens.access_token).active?

    service.revoke(tokens.access_token)

    refute service.introspect(tokens.access_token).active?
  end

  def test_a_handshake_registers_the_app_through_the_fake
    handshake = Masks::Client::Handshake.new(
      issuer.url, name: "app", resource: "https://app.test/mcp", redirect_uris: [ "https://app.test/callback" ],
      return_to: "https://app.test/handshake", scope: %w[openid]
    )
    started = handshake.start
    registration = handshake.complete(returned(issuer.handshake(started[:url])), state: started[:state])

    assert registration.client_id.start_with?("app-")
    refute_nil registration.client_secret
    assert issuer.clients.key?(registration.client_id)
  end
end
