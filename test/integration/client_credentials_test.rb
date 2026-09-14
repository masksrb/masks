require "test_helper"
require_relative "../support/dpop"

class ClientCredentialsTest < ActionDispatch::IntegrationTest
  include DpopProofs

  RESOURCE = "https://uris.example.com/mcp".freeze
  GRANT = Client::CLIENT_CREDENTIALS

  setup do
    host! host_for(@tenant)
    @service = service
  end

  def service(**attributes)
    within do
      client = Client.new(
        client_id: SecureRandom.uuid, name: "Indexer",
        grant_types: [ GRANT ], response_types: [],
        resources: [ RESOURCE ],
        allowed_scopes: "uris:catalog:read uris:catalog:write openid profile masks:manage",
        approved_at: Time.current,
        **attributes
      )

      client.issue_secret! unless client.public?
      client.save!
      client
    end
  end

  def grant(client = @service, secret: client.secret, **params)
    token(grant_type: GRANT, client_id: client.client_id, client_secret: secret, **params)
  end

  test "a service signs in as itself and holds every scope it may on its own behalf" do
    body = grant

    assert_equal "Bearer", body["token_type"]
    assert_equal "uris:catalog:read uris:catalog:write", body["scope"]
    assert_nil body["refresh_token"]
    assert_nil body["id_token"]

    claims = claims_in(body["access_token"])

    assert_equal @service.client_id, claims["sub"]
    assert_equal @service.client_id, claims["client_id"]
    assert_equal RESOURCE, claims["aud"]
  end

  test "a narrower scope is honoured" do
    assert_equal "uris:catalog:read", grant(scope: "uris:catalog:read")["scope"]
  end

  test "a scope that speaks for a person is never held without one" do
    %w[openid profile masks:manage].each do |scope|
      body = grant(scope: scope)

      assert_equal "invalid_scope", body["error"], scope
    end
  end

  test "a scope the client was never allowed is refused" do
    assert_equal "invalid_scope", grant(scope: "uris:catalog:admin")["error"]
  end

  test "a resource the client does not speak for is refused" do
    assert_equal "invalid_target", grant(resource: "https://elsewhere.example.com/mcp")["error"]
  end

  test "a wrong secret is refused" do
    assert_equal "invalid_client", grant(secret: "nope")["error"]
  end

  test "a client not registered for the grant is refused" do
    other = service(grant_types: [ "authorization_code" ], response_types: [ "code" ],
                    redirect_uris: [ OidcFlow::REDIRECT_URI ])

    assert_equal "unauthorized_client", grant(other)["error"]
  end

  test "a public client cannot be given the grant" do
    error = assert_raises(ActiveRecord::RecordInvalid) { service(token_endpoint_auth_method: "none") }

    assert_match "public", error.message
  end

  test "a client nobody approved cannot be given the grant" do
    error = assert_raises(ActiveRecord::RecordInvalid) { service(approved_at: nil) }

    assert_match "approved", error.message
  end

  test "dynamic registration cannot ask for the grant" do
    body = register(grant_types: [ GRANT ], redirect_uris: [])

    assert_equal "invalid_client_metadata", body["error"]
  end

  test "the token reaches no person's userinfo" do
    access = grant["access_token"]

    get "/userinfo", headers: { "HTTP_AUTHORIZATION" => "Bearer #{access}" }

    assert_response :forbidden
  end

  test "introspection names the client as the subject" do
    access = grant["access_token"]

    post "/introspect",
         params: { token: access, client_id: @service.client_id, client_secret: @service.secret }

    body = JSON.parse(response.body)

    assert body["active"]
    assert_equal @service.client_id, body["sub"]
    assert_nil body["username"]
  end

  test "the token can be held to a key" do
    post "/token",
         params: { grant_type: GRANT, client_id: @service.client_id, client_secret: @service.secret },
         headers: with_dpop(method: "POST", url: "#{origin_for(@tenant)}/token")

    body = JSON.parse(response.body)

    assert_equal "DPoP", body["token_type"]
    assert_equal dpop_jkt, claims_in(body["access_token"]).dig("cnf", "jkt")
  end

  test "an exchanged token still names the service it began with" do
    downstream = service(name: "Downstream", grant_types: [ GRANT, Exchange::GRANT_TYPE ])

    body = token(
      grant_type: Exchange::GRANT_TYPE, subject_token: grant["access_token"],
      subject_token_type: Exchange::ACCESS_TOKEN, scope: "uris:catalog:read",
      client_id: downstream.client_id, client_secret: downstream.secret
    )

    claims = claims_in(body["access_token"])

    assert_equal @service.client_id, claims["sub"]
    assert_equal downstream.client_id, claims.dig("act", "sub")
  end

  test "discovery offers the grant" do
    get "/.well-known/openid-configuration"

    assert_includes JSON.parse(response.body)["grant_types_supported"], GRANT
  end

  test "a manager adds a service client and is shown its secret once" do
    manager = create_actor(@tenant, nickname: "manager", scopes: "openid masks:manage")
    console = create_client(@tenant, name: "Console", allowed_scopes: "openid masks:manage",
                                     approved_at: Time.current, grant_types: [ "authorization_code" ])

    created = manage(
      "mutation Add($name: String!, $resources: [String!], $allowedScopes: [String!]) {
        createClient(name: $name, resources: $resources, allowedScopes: $allowedScopes) {
          secret client { clientId grantTypes responseTypes approvedBy { identifier } }
        }
      }",
      bearer: manage_bearer(manager, console),
      name: "Nightly", resources: [ RESOURCE ], allowedScopes: [ "uris:catalog:read" ]
    ).dig("data", "createClient")

    assert_equal [ GRANT ], created.dig("client", "grantTypes")
    assert_empty created.dig("client", "responseTypes")
    assert_equal "manager", created.dig("client", "approvedBy", "identifier")

    body = token(grant_type: GRANT, client_id: created.dig("client", "clientId"), client_secret: created["secret"])

    assert_equal "uris:catalog:read", body["scope"]
  end
end
