require "test_helper"

class ClientAdminTest < ActionDispatch::IntegrationTest
  setup do
    host! host_for(@tenant)

    @actor = create_actor(@tenant, scopes: "openid profile email masks:manage")
    @console = create_client(
      @tenant,
      name: "Console",
      allowed_scopes: "openid profile email masks:manage",
      approved_at: Time.current,
      grant_types: [ "authorization_code", "refresh_token" ]
    )
  end

  def resource
    @resource ||= issuer_for(@tenant).manage_resource
  end

  def bearer
    @bearer ||= begin
      sign_in_as(@actor)
      authorize(client_id: @console.client_id, scope: "openid masks:manage", resource: resource)
      consent! if awaiting_consent?

      token(
        grant_type: "authorization_code",
        code: code_from,
        redirect_uri: OidcFlow::REDIRECT_URI,
        code_verifier: verifier,
        client_id: @console.client_id
      )["access_token"]
    end
  end

  def ask(query, **variables)
    post "/manage/graphql",
         params: { query: query, variables: variables }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer #{bearer}"
         }

    JSON.parse(response.body)
  end

  def probe(**attributes)
    create_client(@tenant, name: "Probe", approved_at: Time.current, **attributes)
  end

  test "the redirect uris a client may use are edited from the console" do
    client = probe

    body = ask(
      "mutation Edit($clientId: ID!, $redirectUris: [String!]) {
        updateClient(clientId: $clientId, redirectUris: $redirectUris) {
          client { redirectUris }
        }
      }",
      clientId: client.client_id,
      redirectUris: [ "https://probe.example.com/cb", "https://probe.example.com/other" ]
    )

    assert_nil body["errors"]
    assert_equal(
      [ "https://probe.example.com/cb", "https://probe.example.com/other" ],
      body["data"]["updateClient"]["client"]["redirectUris"]
    )
  end

  test "a redirect uri that is not usable is refused with a reason" do
    client = probe

    body = ask(
      "mutation Edit($clientId: ID!, $redirectUris: [String!]) {
        updateClient(clientId: $clientId, redirectUris: $redirectUris) { client { clientId } }
      }",
      clientId: client.client_id,
      redirectUris: [ "https://probe.example.com/cb#fragment" ]
    )

    assert_match(/fragment/, body["errors"].to_s)
    assert_equal(
      [ "https://probe.example.com/cb" ],
      within(@tenant) { client.reload.redirect_uris }
    )
  end

  test "a client cannot be left with no redirect uri at all" do
    client = probe

    body = ask(
      "mutation Edit($clientId: ID!, $redirectUris: [String!]) {
        updateClient(clientId: $clientId, redirectUris: $redirectUris) { client { clientId } }
      }",
      clientId: client.client_id,
      redirectUris: []
    )

    assert_match(/at least one/, body["errors"].to_s)
  end

  test "the resources a client may ask a token for are edited from the console" do
    client = probe

    body = ask(
      "mutation Edit($clientId: ID!, $resources: [String!]) {
        updateClient(clientId: $clientId, resources: $resources) { client { resources } }
      }",
      clientId: client.client_id,
      resources: [ "https://api.example.com" ]
    )

    assert_nil body["errors"]
    assert_equal [ "https://api.example.com" ], body["data"]["updateClient"]["client"]["resources"]
  end

  test "an archived client is restored" do
    client = probe
    within(@tenant) { client.update!(archived_at: Time.current) }

    body = ask(
      "mutation Restore($clientId: ID!) {
        restoreClient(clientId: $clientId) { client { archivedAt } }
      }",
      clientId: client.client_id
    )

    assert_nil body["errors"]
    assert_nil body["data"]["restoreClient"]["client"]["archivedAt"]
    assert_nil within(@tenant) { client.reload.archived_at }
    assert within(@tenant) { Event.exists?(action: Event::CLIENT_RESTORED) }
  end

  test "restoring a client is refused when something else answers for its resource now" do
    client = probe(resources: [ "https://api.example.com" ])
    within(@tenant) { client.update!(archived_at: Time.current) }

    create_client(
      @tenant,
      name: "Successor",
      approved_at: Time.current,
      resources: [ "https://api.example.com" ]
    )

    body = ask(
      "mutation Restore($clientId: ID!) {
        restoreClient(clientId: $clientId) { client { archivedAt } }
      }",
      clientId: client.client_id
    )

    assert_match(/Successor/, body["errors"].to_s)
    assert within(@tenant) { client.reload.archived_at.present? }
  end

  test "restoring a client that is not archived is refused" do
    client = probe

    body = ask(
      "mutation Restore($clientId: ID!) {
        restoreClient(clientId: $clientId) { client { archivedAt } }
      }",
      clientId: client.client_id
    )

    assert_match(/not archived/, body["errors"].to_s)
  end
end
