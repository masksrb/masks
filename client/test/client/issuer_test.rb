require_relative "test_helper"

class IssuerTest < ClientTest
  DISCOVERY = "/.well-known/openid-configuration".freeze
  JWKS = "/.well-known/jwks.json".freeze

  def test_the_registry_shares_one_issuer_per_url
    assert_same Masks::Client.issuer(issuer.url), Masks::Client.issuer("#{issuer.url}/")
  end

  def test_a_session_built_per_request_does_not_refetch
    10.times do
      Masks::Client::Session.new(
        issuer: issuer.url, client_id: "app", redirect_uri: "https://app.test/callback"
      ).issuer.endpoint("authorization_endpoint")
    end

    assert_equal 1, issuer.count(DISCOVERY)
  end

  def test_a_resource_built_per_request_does_not_refetch
    header = "Bearer #{issuer.access_token}"

    10.times { resource.authenticate(header) }

    assert_equal 1, issuer.count(DISCOVERY)
    assert_equal 1, issuer.count(JWKS)
  end

  def test_an_unknown_kid_refetches_the_keys_once
    subject = Masks::Client.issuer(issuer.url)
    subject.jwks

    assert_equal 1, issuer.count(JWKS)

    stranger = OpenSSL::PKey::RSA.generate(2048)
    token = issuer.sign(
      { "iss" => issuer.url, "sub" => "a", "aud" => "https://app.test/mcp",
        "exp" => Time.now.to_i + 60 },
      kid: "unknown", key: stranger
    )

    assert_raises(Masks::Client::Unauthorized) { resource.authenticate("Bearer #{token}") }
    assert_operator issuer.count(JWKS), :>, 1
  end

  def test_a_discovery_document_naming_another_issuer_is_refused
    subject = Masks::Client.issuer(issuer.url)
    issuer.override(DISCOVERY, issuer.discovery.merge("issuer" => "https://elsewhere.test"))

    error = assert_raises(Masks::Client::Rejected) { subject.discovery }

    assert_equal "invalid_issuer", error.code
    assert_includes error.description, "elsewhere.test"
  end

  def test_a_missing_endpoint_is_named
    subject = Masks::Client.issuer(issuer.url)
    issuer.override(DISCOVERY, issuer.discovery.reject { |key, _| key == "token_endpoint" })

    error = assert_raises(Masks::Client::Rejected) { subject.endpoint("token_endpoint") }

    assert_includes error.description, "token_endpoint"
  end

  def test_refresh_clears_the_cache
    subject = Masks::Client.issuer(issuer.url)
    subject.discovery
    subject.refresh!
    subject.discovery

    assert_equal 2, issuer.count(DISCOVERY)
  end

  def test_an_unreachable_issuer_says_so
    dead = Masks::Client.issuer("http://127.0.0.1:1")

    assert_raises(Masks::Client::Unreachable) { dead.discovery }
  end

  def test_the_tenant_travels_in_the_discovery_document
    assert_equal "demo", Masks::Client.issuer(issuer.url).tenant["subdomain"]
  end
end
