require_relative "test_helper"

class ResourceTest < ClientTest
  def test_a_valid_token_becomes_claims
    claims = resource.authenticate("Bearer #{issuer.access_token}")

    assert_equal "actor-1", claims.subject
    assert_equal issuer.url, claims.issuer
    assert_equal %w[things:read things:write], claims.scopes
    assert_equal [ "https://app.test/mcp" ], claims.audience
    refute claims.expired?
  end

  def test_the_tenant_claim_arrives_as_an_identity
    tenant = resource.authenticate("Bearer #{issuer.access_token}").tenant

    assert_equal "t-1", tenant.uuid
    assert_equal "demo", tenant.subdomain
    assert_equal "Demo", tenant.name
    assert tenant.present?
  end

  def test_a_missing_header_is_401_without_an_error_code
    error = assert_raises(Masks::Client::Unauthenticated) { resource.authenticate(nil) }

    assert_equal 401, error.status
    assert_nil error.code
    refute_includes resource.challenge(error), "error="
  end

  def test_a_header_that_is_not_bearer_is_refused
    assert_raises(Masks::Client::Unauthenticated) { resource.authenticate("Basic abc") }
  end

  def test_a_token_for_another_audience_is_refused
    token = issuer.access_token(audience: "https://other.test/mcp")

    error = assert_raises(Masks::Client::Unauthorized) { resource.authenticate("Bearer #{token}") }

    assert_equal 401, error.status
    assert_equal "invalid_token", error.code
  end

  def test_an_expired_token_is_refused
    token = issuer.access_token(expires_in: -60)

    assert_raises(Masks::Client::Unauthorized) { resource.authenticate("Bearer #{token}") }
  end

  def test_a_token_signed_by_an_unpublished_key_is_refused
    stranger = OpenSSL::PKey::RSA.generate(2048)
    token = issuer.sign(
      { "iss" => issuer.url, "sub" => "a", "aud" => "https://app.test/mcp",
        "exp" => Time.now.to_i + 60 },
      kid: "not-published", key: stranger
    )

    assert_raises(Masks::Client::Unauthorized) { resource.authenticate("Bearer #{token}") }
  end

  def test_a_token_from_another_issuer_is_refused
    other = FakeIssuer.new
    token = other.access_token

    assert_raises(Masks::Client::Unauthorized) { resource.authenticate("Bearer #{token}") }
  ensure
    other&.stop
  end

  def test_a_required_scope_is_enforced
    token = issuer.access_token(scope: "things:read")

    error = assert_raises(Masks::Client::Forbidden) do
      resource.authenticate("Bearer #{token}", scope: "resources:command")
    end

    assert_equal 403, error.status
    assert_equal "insufficient_scope", error.code
    assert_equal "resources:command", error.scope
  end

  def test_a_granted_scope_passes
    claims = resource.authenticate("Bearer #{issuer.access_token}", scope: "things:read")

    assert claims.permits?("things:write")
    refute claims.permits?("resources:command")
  end

  def test_the_challenge_carries_the_metadata_url_and_scopes
    challenge = resource.challenge(Masks::Client::Unauthorized.new("nope"))

    assert_includes challenge, 'error="invalid_token"'
    assert_includes challenge, 'error_description="nope"'
    assert_includes challenge, 'scope="things:read things:write resources:command"'
    assert_includes challenge,
                    'resource_metadata="https://app.test/.well-known/oauth-protected-resource"'
  end

  def test_a_description_cannot_break_out_of_the_challenge
    challenge = resource.challenge(Masks::Client::Unauthorized.new(%(a "quoted" \\ value\nand more)))

    described = challenge[/error_description="([^"]*)"/, 1]

    assert_equal 1, challenge.scan(/error_description="/).size
    assert_equal "a  quoted    value and more", described
    refute_includes challenge, "\n"
    assert_equal 8, challenge.count('"')
  end

  def test_metadata_answers_the_rfc_9728_document
    assert_equal(
      {
        "resource" => "https://app.test/mcp",
        "authorization_servers" => [ issuer.url ],
        "scopes_supported" => %w[things:read things:write resources:command],
        "bearer_methods_supported" => [ "header" ]
      },
      resource.metadata
    )
  end

  def test_described_scopes_are_published_beside_the_names_they_describe
    described = Masks::Client::Resource.new(
      issuer: issuer.url,
      url: "https://app.test/mcp",
      scopes: { "things:read" => "Search and read your catalog" }
    )

    assert_equal %w[things:read], described.scopes
    assert_equal({ "things:read" => "Search and read your catalog" },
                 described.metadata["scope_descriptions"])
  end

  def test_a_resource_with_no_scopes_publishes_no_empty_lists
    bare = Masks::Client::Resource.new(issuer: issuer.url, url: "https://app.test/mcp")

    assert_nil bare.metadata["scopes_supported"]
    assert_nil bare.metadata["scope_descriptions"]
  end

  def test_the_metadata_url_is_derived_from_the_origin_not_the_path
    assert_equal(
      "https://app.test/.well-known/oauth-protected-resource",
      resource(url: "https://app.test/deep/nested/mcp").metadata_url
    )
  end
end
