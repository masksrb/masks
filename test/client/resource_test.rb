require_relative "test_helper"

class ResourceTest < ClientTest
  def test_a_valid_token_becomes_claims
    claims = resource.authenticate("Bearer #{issuer.access_token}")

    assert_equal "actor-1", claims.subject
    assert_equal issuer.url, claims.issuer
    assert_equal %w[uris:catalog:read uris:catalog:write], claims.scopes
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

  def organized(role: "member", key: "acme")
    issuer.access_token("org" => { "id" => "o-1", "key" => key, "name" => key.capitalize, "role" => role })
  end

  def test_the_organization_claim_arrives_with_the_role_held_in_it
    organization = resource.authenticate("Bearer #{organized(role: 'owner')}").organization

    assert_equal "o-1", organization.id
    assert_equal "acme", organization.key
    assert_equal "Acme", organization.name
    assert organization.owner?
    assert organization.role?("admin", "owner")
    refute organization.role?("admin")
  end

  def test_a_token_naming_no_organization_holds_no_role
    organization = resource.authenticate("Bearer #{issuer.access_token}").organization

    refute organization.present?
    refute organization.role?("owner")
    refute organization.owner?
  end

  def test_a_role_asked_for_is_held_or_the_token_is_forbidden
    assert_equal "acme", resource.authenticate("Bearer #{organized(role: 'owner')}", role: %w[admin owner]).organization.key

    error = assert_raises(Masks::Client::Forbidden) { resource.authenticate("Bearer #{organized}", role: "owner") }

    assert_equal 403, error.status
    assert_equal "insufficient_role", error.code
  end

  def test_an_organization_asked_for_is_the_one_the_token_names
    assert resource.authenticate("Bearer #{organized}", organization: "acme")
    assert resource.authenticate("Bearer #{organized}", organization: "o-1")

    error = assert_raises(Masks::Client::Forbidden) { resource.authenticate("Bearer #{organized}", organization: "globex") }

    assert_equal "insufficient_organization", error.code
  end

  def test_a_token_without_an_organization_is_forbidden_where_one_is_required
    error = assert_raises(Masks::Client::Forbidden) { resource.authenticate("Bearer #{issuer.access_token}", role: "member") }

    assert_equal "insufficient_organization", error.code
    assert_includes resource.challenge(error), %(scope="organization")
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

  def test_an_id_token_is_not_accepted_as_an_access_token
    claims = JWT.decode(issuer.access_token, nil, false).first

    assert_raises(Masks::Client::Unauthorized) { resource.authenticate("Bearer #{issuer.sign(claims)}") }
  end

  def test_the_media_type_form_of_the_access_token_type_is_accepted
    claims = JWT.decode(issuer.access_token, nil, false).first

    assert resource.authenticate("Bearer #{issuer.sign(claims, typ: 'application/at+jwt')}")
  end

  def test_a_required_scope_is_enforced
    token = issuer.access_token(scope: "uris:catalog:read")

    error = assert_raises(Masks::Client::Forbidden) do
      resource.authenticate("Bearer #{token}", scope: "resources:command")
    end

    assert_equal 403, error.status
    assert_equal "insufficient_scope", error.code
    assert_equal "resources:command", error.scope
  end

  def test_a_granted_scope_passes
    claims = resource.authenticate("Bearer #{issuer.access_token}", scope: "uris:catalog:read")

    assert claims.permits?("uris:catalog:write")
    refute claims.permits?("resources:command")
  end

  def test_the_challenge_carries_the_metadata_url_and_scopes
    challenge = resource.challenge(Masks::Client::Unauthorized.new("nope"))

    assert_includes challenge, 'error="invalid_token"'
    assert_includes challenge, 'error_description="nope"'
    assert_includes challenge, 'scope="uris:catalog:read uris:catalog:write resources:command"'
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
        "scopes_supported" => %w[uris:catalog:read uris:catalog:write resources:command],
        "bearer_methods_supported" => [ "header" ]
      },
      resource.metadata
    )
  end

  def test_described_scopes_are_published_beside_the_names_they_describe
    described = Masks::Client::Resource.new(
      issuer: issuer.url,
      url: "https://app.test/mcp",
      scopes: { "uris:catalog:read" => "Search and read your catalog" }
    )

    assert_equal %w[uris:catalog:read], described.scopes
    assert_equal({ "uris:catalog:read" => "Search and read your catalog" },
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
