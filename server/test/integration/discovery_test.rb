require "test_helper"

class DiscoveryTest < ActionDispatch::IntegrationTest
  setup { host! host_for(@tenant) }

  def document(path = "/.well-known/openid-configuration", tenant = @tenant)
    host! host_for(tenant)
    get path

    JSON.parse(response.body)
  end

  test "discovery names this tenant and this origin" do
    body = document

    assert_response :success
    assert_equal origin_for(@tenant), body["issuer"]
    assert_equal @tenant.uuid, body.dig("tenant", "uuid")
    assert_equal @tenant.subdomain, body.dig("tenant", "subdomain")
  end

  test "the oauth authorization server document answers the same" do
    assert_equal document, document("/.well-known/oauth-authorization-server")
  end

  test "every advertised endpoint sits under the issuer" do
    body = document

    %w[authorization_endpoint token_endpoint userinfo_endpoint jwks_uri
       registration_endpoint revocation_endpoint end_session_endpoint].each do |endpoint|
      assert body[endpoint].start_with?(body["issuer"]),
             "#{endpoint} is not under the issuer"
    end
  end

  test "discovery advertises what the implementation actually supports" do
    body = document

    assert_equal [ "S256" ], body["code_challenge_methods_supported"]
    assert_equal [ "code" ], body["response_types_supported"]
    assert_includes body["grant_types_supported"], Exchange::GRANT_TYPE
    assert body["authorization_response_iss_parameter_supported"]
    assert body["resource_indicators_supported"]
  end

  test "each tenant's discovery names its own origin" do
    assert_equal origin_for(@tenant), document["issuer"]
    assert_equal origin_for(other_tenant),
                 document("/.well-known/openid-configuration", other_tenant)["issuer"]
  end

  test "each tenant publishes its own key" do
    mine = document("/.well-known/jwks.json")["keys"]
    theirs = document("/.well-known/jwks.json", other_tenant)["keys"]

    assert_equal 1, mine.length
    assert_equal 1, theirs.length
    assert_not_equal mine.first["kid"], theirs.first["kid"]
  end

  test "a published key carries only its public half" do
    key = document("/.well-known/jwks.json")["keys"].first

    assert_equal %w[kty use alg kid n e].sort, key.keys.sort
    assert_equal "RS256", key["alg"]
  end

  test "a rotation publishes both keys and keeps outgoing tokens verifiable" do
    actor = create_actor
    registration = register
    host! host_for(@tenant)
    issued = access_token_for(actor: actor, registration: registration)["access_token"]

    outgoing = JWT.decode(issued, nil, false).last["kid"]
    within { SigningKey.rotate!(tenant: @tenant) }

    keys = document("/.well-known/jwks.json")["keys"]
    assert_equal 2, keys.length
    assert_includes keys.map { |key| key["kid"] }, outgoing

    assert_nothing_raised { claims_in(issued) }

    get "/userinfo", headers: { "HTTP_AUTHORIZATION" => "Bearer #{issued}" }
    assert_response :success
  end

  test "a new token after a rotation carries the new kid" do
    actor = create_actor
    registration = register
    host! host_for(@tenant)
    before = JWT.decode(
      access_token_for(actor: actor, registration: registration)["access_token"], nil, false
    ).last["kid"]

    within { SigningKey.rotate!(tenant: @tenant) }

    reset!
    host! host_for(@tenant)
    after = JWT.decode(
      access_token_for(actor: actor, registration: registration)["access_token"], nil, false
    ).last["kid"]

    assert_not_equal before, after
  end

  test "an unknown hostname serves no tenant" do
    host! "nobody.auth.test"
    get "/.well-known/openid-configuration"

    assert_response :not_found
  end
end
