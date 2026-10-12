require_relative "test_helper"

class MachineTest < ClientTest
  API = "https://api.test".freeze

  def key
    @key ||= Masks::Client::Key.generate
  end

  def dpop
    @dpop ||= Masks::Client::Key.generate
  end

  def machine(**options)
    Masks::Client::Session.new(issuer: issuer.url, client_id: "machine-1", private_key: key, dpop: dpop, **options)
  end

  def bound(token = "at", **extra)
    { "access_token" => token, "token_type" => "DPoP", "expires_in" => 3600 }.merge(extra.transform_keys(&:to_s))
  end

  def sent(path)
    issuer.received.select { |held| held[:path] == path }
  end

  def proved(request)
    proof = request[:headers]["dpop"]
    header = JWT.decode(proof, nil, false).last
    claims = JWT.decode(proof, JWT::JWK.new(header["jwk"]).verify_key, true, algorithms: [ "ES256" ]).first

    assert_equal "dpop+jwt", header["typ"]
    assert_equal dpop.thumbprint, Masks::Client::Proof.thumbprint(header["jwk"])
    assert_equal [ request[:method], "#{issuer.url}#{request[:path]}" ], claims.values_at("htm", "htu")
    assert_nil claims["ath"]

    claims
  end

  def test_a_machine_enrolls_with_its_public_key_and_signs_in_with_the_private_half
    issuer.override("/register", [ 201, {
      "client_id" => "machine-1", "client_name" => "nas", "token_endpoint_auth_method" => "private_key_jwt",
      "grant_types" => [ "client_credentials" ], "dpop_bound_access_tokens" => true,
      "registration_access_token" => "rat", "registration_client_uri" => "#{issuer.url}/register/machine-1"
    } ])
    issuer.override("/token", bound(scope: "xixo:agent"))

    registration = Masks::Client::Registration.create(
      issuer.url, token: "iat", name: "nas", jwks: key, token_endpoint_auth_method: "private_key_jwt",
                  grant_types: [ "client_credentials" ], dpop_bound_access_tokens: true
    )
    registered = issuer.last("/register")
    tokens = registration.session(private_key: key, dpop: dpop).client_credentials(scope: "xixo:agent")
    asked = issuer.last("/token")
    assertion, header = JWT.decode(asked[:body]["client_assertion"], key.private_key, true, algorithms: [ "ES256" ])

    assert_equal "Bearer iat", registered[:headers]["authorization"]
    assert_equal key.jwks, registered[:body]["jwks"]
    refute registered[:body]["jwks"]["keys"].first.key?("d")
    assert_equal [ "private_key_jwt", [ "client_credentials" ], true ],
                 registered[:body].values_at("token_endpoint_auth_method", "grant_types", "dpop_bound_access_tokens")
    assert_nil registration.client_secret

    assert_predicate tokens, :bound?
    assert_equal "DPoP at", tokens.authorization
    assert_equal key.thumbprint, header["kid"]
    assert_equal [ "machine-1", "machine-1", issuer.url ], assertion.values_at("iss", "sub", "aud")
    assert_nil asked[:headers]["authorization"]
    proved(asked)
  end

  def test_enrollment_registers_where_discovery_publishes_no_registration_endpoint
    issuer.override("/.well-known/openid-configuration", issuer.discovery.except("registration_endpoint"))
    issuer.override("/register", [ 201, { "client_id" => "machine-1" } ])

    Masks::Client::Registration.create(issuer.url, token: "iat", jwks: key)

    assert_equal "Bearer iat", issuer.last("/register")[:headers]["authorization"]
  end

  def test_open_registration_still_needs_a_published_endpoint
    issuer.override("/.well-known/openid-configuration", issuer.discovery.except("registration_endpoint"))

    assert_raises(Masks::Client::Rejected) { Masks::Client::Registration.create(issuer.url, jwks: key) }
    assert_equal 0, issuer.count("/register")
  end

  def test_a_registration_naming_another_origin_keeps_its_token_to_itself
    registration = Masks::Client::Registration.new(
      Masks::Client::Issuer.resolve(issuer.url),
      { "client_id" => "machine-1", "registration_access_token" => "rat",
        "registration_client_uri" => "https://elsewhere.test/register/machine-1" }
    )

    assert_raises(Masks::Client::Foreign) { registration.read }
    assert_raises(Masks::Client::Foreign) { registration.update(jwks: key) }
    assert_raises(Masks::Client::Foreign) { registration.delete }
  end

  def test_every_token_request_carries_a_new_proof
    issuer.override("/token", bound(refresh_token: "rt"))
    session = machine

    session.client_credentials
    session.refresh("rt")
    session.exchange("subject")

    proofs = sent("/token").map { |request| proved(request) }

    assert_equal 3, proofs.map { |claims| claims["jti"] }.uniq.size
    assert_equal [ "client_credentials", "refresh_token", Masks::Client::Tokens::EXCHANGE ],
                 sent("/token").map { |request| request[:body]["grant_type"] }
  end

  def test_requests_off_the_token_endpoint_carry_no_proof
    issuer.override("/revoke", {})
    issuer.override("/introspect", { "active" => false })

    machine.revoke("at")
    machine.introspect("at")

    assert_nil issuer.last("/revoke")[:headers]["dpop"]
    assert_nil issuer.last("/introspect")[:headers]["dpop"]
  end

  def test_a_bearer_answered_to_a_proven_request_is_refused
    issuer.override("/token", bound.merge("token_type" => "Bearer"))

    error = assert_raises(Masks::Client::Rejected) { machine.client_credentials }

    assert_equal "invalid_dpop_proof", error.code
  end

  def test_the_token_endpoint_asking_for_a_nonce_is_answered_once
    answers = [ [ 400, { "error" => "use_dpop_nonce" }, { "DPoP-Nonce" => "n-1" } ], bound ]
    issuer.override("/token", ->(_) { answers.size > 1 ? answers.shift : answers.first })
    session = machine

    session.client_credentials
    session.client_credentials

    nonces = sent("/token").map { |request| proved(request)["nonce"] }
    assertions = sent("/token").map { |request| request[:body]["client_assertion"] }

    assert_equal [ nil, "n-1", "n-1" ], nonces
    assert_equal 3, assertions.uniq.size
  end

  def test_a_nonce_asked_for_twice_is_not_chased
    issuer.override("/token", [ 400, { "error" => "use_dpop_nonce" }, { "DPoP-Nonce" => "n-1" } ])

    error = assert_raises(Masks::Client::Rejected) { machine.client_credentials }

    assert_equal "use_dpop_nonce", error.code
    assert_equal 2, issuer.count("/token")
  end

  def test_a_refusal_without_a_new_nonce_is_not_retried
    issuer.override("/token", [ 400, { "error" => "invalid_dpop_proof", "error_description" => "that proof was made for another URL" } ])

    assert_raises(Masks::Client::Rejected) { machine.client_credentials }
    assert_equal 1, issuer.count("/token")
  end

  def test_a_dpop_key_must_be_p256
    assert_raises(ArgumentError) do
      Masks::Client::Session.new(issuer: issuer.url, client_id: "m", dpop: OpenSSL::PKey::EC.generate("secp384r1"))
    end
  end

  def test_a_transport_sends_a_bound_token_with_a_proof_naming_it
    issuer.override("/token", bound)
    issuer.override("/api/feeds?page=2", { "feeds" => [] })

    response = machine.transport(issuer.url).get("#{issuer.url}/api/feeds?page=2")
    request = issuer.last("/api/feeds?page=2")
    claims = JWT.decode(request[:headers]["dpop"], nil, false).first

    assert_equal "200", response.code
    assert_equal "DPoP at", request[:headers]["authorization"]
    assert_equal "#{issuer.url}/api/feeds", claims["htu"]
    Masks::Client::Proof.new(request[:headers]["dpop"], method: "GET", url: "#{issuer.url}/api/feeds")
                        .check!(access_token: "at", jkt: dpop.thumbprint)
  end

  def test_a_transport_refuses_an_origin_it_was_not_given
    transport = machine.transport(API)

    assert_raises(Masks::Client::Foreign) { transport.get("#{issuer.url}/api") }
    assert_raises(Masks::Client::Foreign) { transport.get("https://api.test.evil.example/") }
    assert_raises(Masks::Client::Foreign) { transport.get("http://api.test/") }
    assert_equal 0, issuer.count("/token")
  end

  def test_a_transport_names_its_origins_without_paths_or_default_ports
    transport = Masks::Client::Transport.new("HTTPS://API.test:443/v1", tokens: Masks::Client::Tokens.new(bound))

    assert_equal [ API ], transport.origins
  end

  def test_a_transport_reuses_its_tokens_until_they_expire
    issuer.override("/token", bound(expires_in: 3600))
    issuer.override("/api", {})
    transport = machine.transport(issuer.url)

    transport.get("#{issuer.url}/api")
    transport.post("#{issuer.url}/api", body: { "a" => 1 })

    assert_equal 1, issuer.count("/token")
    assert_equal({ "a" => 1 }, issuer.last("/api")[:body])
    assert_equal "application/json", issuer.last("/api")[:headers]["content-type"]
  end

  def test_a_transport_holding_tokens_refreshes_them_and_keeps_the_refresh_token
    issuer.override("/token", bound("fresh"))
    issuer.override("/api", {})
    expired = Masks::Client::Tokens.new(bound("stale", "expires_in" => 0, "refresh_token" => "rt"))
    kept = []

    machine.transport(issuer.url, tokens: expired) { |tokens| kept << tokens }.get("#{issuer.url}/api")

    assert_equal "rt", issuer.last("/token")[:body]["refresh_token"]
    assert_equal "DPoP fresh", issuer.last("/api")[:headers]["authorization"]
    assert_equal [ [ "fresh", "rt" ] ], kept.map { |tokens| [ tokens.access_token, tokens.refresh_token ] }
  end

  def test_a_transport_with_no_refresh_token_to_renew_with_is_refused
    expired = Masks::Client::Tokens.new(bound("stale", "expires_in" => 0))

    error = assert_raises(Masks::Client::Rejected) { machine.transport(issuer.url, tokens: expired).get("#{issuer.url}/api") }

    assert_equal "invalid_grant", error.code
  end

  def test_a_resource_asking_for_a_nonce_is_answered_once
    issuer.override("/token", bound)
    answers = [ [ 401, { "error" => "use_dpop_nonce" }, { "WWW-Authenticate" => 'DPoP error="use_dpop_nonce"', "DPoP-Nonce" => "r-1" } ], {} ]
    issuer.override("/api", ->(_) { answers.size > 1 ? answers.shift : answers.first })

    response = machine.transport(issuer.url).get("#{issuer.url}/api")
    nonces = sent("/api").map { |request| JWT.decode(request[:headers]["dpop"], nil, false).first["nonce"] }

    assert_equal "200", response.code
    assert_equal [ nil, "r-1" ], nonces
  end

  def test_a_resource_refusal_without_a_nonce_challenge_is_answered_as_is
    issuer.override("/token", bound)
    issuer.override("/api", [ 401, { "error" => "invalid_token" }, { "WWW-Authenticate" => 'DPoP error="invalid_token"', "DPoP-Nonce" => "r-1" } ])

    assert_equal "401", machine.transport(issuer.url).get("#{issuer.url}/api").code
    assert_equal 1, issuer.count("/api")
  end

  def test_a_bearer_token_travels_as_a_bearer_without_a_proof
    issuer.override("/api", {})
    transport = Masks::Client::Transport.new(issuer.url, tokens: Masks::Client::Tokens.new(bound.merge("token_type" => "Bearer")))

    transport.get("#{issuer.url}/api")

    assert_equal "Bearer at", issuer.last("/api")[:headers]["authorization"]
    assert_nil issuer.last("/api")[:headers]["dpop"]
  end

  def test_a_bound_token_without_its_key_is_not_sent
    transport = Masks::Client::Transport.new(issuer.url, tokens: Masks::Client::Tokens.new(bound))

    assert_raises(Masks::Client::Error) { transport.get("#{issuer.url}/api") }
    assert_equal 0, issuer.count("/api")
  end

  def test_userinfo_presents_a_bound_token_with_a_proof_naming_it
    issuer.override("/userinfo", { "sub" => "machine-1" })
    tokens = Masks::Client::Tokens.new(bound)

    assert_equal "machine-1", machine.userinfo(tokens)["sub"]

    request = issuer.last("/userinfo")

    assert_equal "DPoP at", request[:headers]["authorization"]
    Masks::Client::Proof.new(request[:headers]["dpop"], method: "GET", url: "#{issuer.url}/userinfo")
                        .check!(access_token: "at", jkt: dpop.thumbprint)
  end

  def test_userinfo_presents_a_bearer_token_or_a_bare_string_as_a_bearer
    issuer.override("/userinfo", { "sub" => "actor-1" })

    machine.userinfo(Masks::Client::Tokens.new(bound.merge("token_type" => "Bearer")))

    assert_equal "Bearer at", issuer.last("/userinfo")[:headers]["authorization"]
    assert_nil issuer.last("/userinfo")[:headers]["dpop"]

    machine.userinfo("plain")

    assert_equal "Bearer plain", issuer.last("/userinfo")[:headers]["authorization"]
  end

  def test_userinfo_will_not_present_a_bound_token_without_its_key
    session = Masks::Client::Session.new(issuer: issuer.url, client_id: "app", client_secret: "shh")

    assert_raises(Masks::Client::Error) { session.userinfo(Masks::Client::Tokens.new(bound)) }
    assert_equal 0, issuer.count("/userinfo")
  end

  def test_a_transport_refuses_a_plain_http_origin_off_loopback
    assert_raises(Masks::Client::Insecure) { machine.transport("http://api.example.com") }
  end

  def test_a_machine_registration_sends_no_grant_or_response_types_it_was_not_given
    issuer.override("/register", [ 201, { "client_id" => "machine-1" } ])

    Masks::Client::Registration.create(issuer.url, token: "iat", name: "nas", jwks: key)
    body = issuer.last("/register")[:body]

    refute body.key?("grant_types")
    refute body.key?("response_types")
    assert_equal key.jwks, body["jwks"]
  end
end
