require "test_helper"

class IntrospectionTest < ActionDispatch::IntegrationTest
  RESOURCE = "https://uris.example.com/mcp".freeze

  setup do
    host! host_for(@tenant)
    @actor = create_actor(@tenant, scopes: "openid profile email offline_access uris:read")
  end

  def introspect(token, client_id:, client_secret:, **params)
    post "/introspect",
         params: { token: token }.merge(params),
         headers: { "HTTP_AUTHORIZATION" => basic(client_id, client_secret) }

    JSON.parse(response.body)
  end

  def basic(id, secret)
    "Basic #{Base64.strict_encode64("#{id}:#{secret}")}"
  end

  def granted(scope: "openid profile uris:read", resource: RESOURCE)
    registered = register(scope: scope, resources: [ resource ])

    sign_in_as(@actor)

    tokens = authorize_and_exchange(registered, scope: scope, resource: resource)

    [ registered, tokens ]
  end

  def authorize_and_exchange(registered, scope:, resource:)
    get "/authorize", params: {
      response_type: "code", client_id: registered["client_id"],
      redirect_uri: OidcFlow::REDIRECT_URI, scope: scope,
      state: "s", resource: resource,
      code_challenge: challenge, code_challenge_method: "S256"
    }

    follow_consent

    code = Rack::Utils.parse_query(URI.parse(response.location).query)["code"]

    post "/token", params: {
      grant_type: "authorization_code", code: code,
      redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier
    }, headers: { "HTTP_AUTHORIZATION" => basic(registered["client_id"], registered["client_secret"]) }

    JSON.parse(response.body)
  end

  def follow_consent
    consent! if awaiting_consent?
  end

  test "discovery advertises the endpoint" do
    get "/.well-known/openid-configuration"

    document = JSON.parse(response.body)

    assert_equal "#{origin_for(@tenant)}/introspect", document["introspection_endpoint"]
    assert_equal Client::AUTH_METHODS, document["introspection_endpoint_auth_methods_supported"]
  end

  test "the client a token was issued to learns what it carries" do
    registered, tokens = granted

    body = introspect(tokens["access_token"],
                      client_id: registered["client_id"],
                      client_secret: registered["client_secret"])

    assert_equal true, body["active"]
    assert_equal "Bearer", body["token_type"]
    assert_equal registered["client_id"], body["client_id"]
    assert_equal @actor.nickname, body["username"]
    assert_includes body["scope"].split(" "), "uris:read"
    assert_equal [ RESOURCE ], body["aud"]
    assert_equal origin_for(@tenant), body["iss"]
    assert body["exp"] > Time.current.to_i
  end

  test "a revoked token reads as inactive immediately, which is the whole point" do
    registered, tokens = granted

    post "/revoke", params: { token: tokens["access_token"] },
                    headers: { "HTTP_AUTHORIZATION" => basic(registered["client_id"], registered["client_secret"]) }

    assert_response :success

    body = introspect(tokens["access_token"],
                      client_id: registered["client_id"],
                      client_secret: registered["client_secret"])

    assert_equal({ "active" => false }, body)
  end

  test "a refresh token introspects too" do
    registered, tokens = granted(scope: "openid offline_access uris:read")

    body = introspect(tokens["refresh_token"],
                      client_id: registered["client_id"],
                      client_secret: registered["client_secret"],
                      token_type_hint: "refresh_token")

    assert_equal true, body["active"]
    assert_nil body["token_type"]
  end

  test "a resource server named in the audience may ask about a token presented to it" do
    _issuedto, tokens = granted

    server = register(client_name: "resource server", resources: [ RESOURCE ])

    body = introspect(tokens["access_token"],
                      client_id: server["client_id"],
                      client_secret: server["client_secret"])

    assert_equal true, body["active"]
  end

  test "a stranger's client learns nothing, and learns it the same way a revoked token does" do
    _issuedto, tokens = granted

    stranger = register(client_name: "stranger", resources: [ "https://elsewhere.example.com" ])

    body = introspect(tokens["access_token"],
                      client_id: stranger["client_id"],
                      client_secret: stranger["client_secret"])

    assert_equal({ "active" => false }, body)
  end

  test "an unauthenticated caller is refused rather than answered" do
    _registered, tokens = granted

    post "/introspect", params: { token: tokens["access_token"] }

    assert_response :unauthorized
    assert_equal "invalid_client", JSON.parse(response.body)["error"]
  end

  test "a token that never existed is inactive rather than an error" do
    registered = register

    body = introspect("not-a-token",
                      client_id: registered["client_id"],
                      client_secret: registered["client_secret"])

    assert_equal({ "active" => false }, body)
  end

  test "an inactive answer carries nothing else at all" do
    registered = register

    body = introspect("not-a-token",
                      client_id: registered["client_id"],
                      client_secret: registered["client_secret"])

    assert_equal [ "active" ], body.keys
  end
end
