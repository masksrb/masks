require "test_helper"

class ProviderAdminTest < ActionDispatch::IntegrationTest
  CREATE = <<~GQL.freeze
    mutation Add(
      $key: ID!, $name: String!, $authorizationUrl: String!, $tokenUrl: String!,
      $clientId: String!, $clientSecret: String, $scopes: [String!],
      $authorizeParams: JSON
    ) {
      createProvider(
        key: $key, name: $name, authorizationUrl: $authorizationUrl, tokenUrl: $tokenUrl,
        clientId: $clientId, clientSecret: $clientSecret, scopes: $scopes,
        authorizeParams: $authorizeParams
      ) {
        provider { key name releaseScope secretHeld scopes connections }
      }
    }
  GQL

  setup do
    host! host_for(@tenant)

    @admin = create_actor(@tenant, nickname: "admin", scopes: "openid profile email masks:manage")
    @client = create_client(
      @tenant,
      allowed_scopes: "openid profile email masks:manage",
      approved_at: Time.current,
      grant_types: [ "authorization_code", "refresh_token" ]
    )
  end

  def token!
    sign_in_as(@admin)
    authorize(
      client_id: @client.client_id,
      scope: "openid masks:manage",
      resource: issuer_for(@tenant).manage_resource
    )
    consent! if awaiting_consent?

    token(
      grant_type: "authorization_code",
      code: code_from,
      redirect_uri: OidcFlow::REDIRECT_URI,
      code_verifier: verifier,
      client_id: @client.client_id
    )["access_token"]
  end

  def ask(query, **variables)
    @token ||= token!

    post "/manage/graphql",
         params: { query: query, variables: variables }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer #{@token}"
         }

    JSON.parse(response.body)
  end

  def add(**overrides)
    ask(
      CREATE,
      **{
        key: "google",
        name: "Google",
        authorizationUrl: "https://accounts.google.com/o/oauth2/v2/auth",
        tokenUrl: "https://oauth2.googleapis.com/token",
        clientId: "upstream-client",
        clientSecret: "upstream-secret",
        scopes: [ "https://www.googleapis.com/auth/drive.readonly" ]
      }.merge(overrides)
    )
  end

  test "a provider added through the console is one people can connect" do
    answer = add

    assert_nil answer["errors"]

    held = answer["data"]["createProvider"]["provider"]

    assert_equal "masks:connections:google", held["releaseScope"]
    assert held["secretHeld"], "the secret was stored"
    assert_equal 0, held["connections"]

    get "/connections/google/start"

    assert_response :redirect
    assert response.location.start_with?("https://accounts.google.com/o/oauth2/v2/auth"),
           "the provider the console added is the one the browser is sent to"
  end

  test "the secret is stored but never handed back" do
    add

    answer = ask("query One($key: ID!) { provider(key: $key) { name secretHeld } }", key: "google")

    assert_equal "Google", answer["data"]["provider"]["name"]
    assert answer["data"]["provider"]["secretHeld"]
    assert_not response.body.include?("upstream-secret"),
               "a client secret has no business leaving the server"
  end

  test "a token endpoint over plain http is refused unless it is loopback" do
    answer = add(tokenUrl: "http://accounts.example.com/token")

    assert_not_nil answer["errors"]
    assert_match(/https/, answer["errors"].first["message"])
    assert_equal 0, within(@tenant) { Provider.count }
  end

  test "loopback is allowed, because that is what running one locally looks like" do
    answer = add(tokenUrl: "http://127.0.0.1:9999/token")

    assert_nil answer["errors"]
  end

  test "authorize params may not take over the parameters the request builds" do
    answer = add(authorizeParams: { "redirect_uri" => "https://elsewhere.example.com/cb" })

    assert_not_nil answer["errors"]
    assert_match(/redirect_uri/, answer["errors"].first["message"])
  end

  test "authorize params carry the extras a provider asks for" do
    answer = add(authorizeParams: { "access_type" => "offline", "prompt" => "consent" })

    assert_nil answer["errors"]

    get "/connections/google/start"

    assert_includes response.location, "access_type=offline"
    assert_includes response.location, "prompt=consent"
  end

  test "a key is claimed once" do
    add

    answer = add(name: "Google Again")

    assert_not_nil answer["errors"]
    assert_match(/already keyed/, answer["errors"].first["message"])
  end

  test "editing leaves the secret alone unless a new one is sent" do
    add

    answer = ask(<<~GQL, key: "google", name: "Google Workspace")
      mutation Edit($key: ID!, $name: String!) {
        updateProvider(key: $key, name: $name) { provider { name secretHeld } }
      }
    GQL

    assert_nil answer["errors"]
    assert_equal "Google Workspace", answer["data"]["updateProvider"]["provider"]["name"]
    assert answer["data"]["updateProvider"]["provider"]["secretHeld"]

    assert_equal "upstream-secret", within(@tenant) { Provider.find_by(key: "google").client_secret }
  end

  test "archiving takes the provider out of reach, and restoring puts it back" do
    add

    assert_nil ask("mutation Off($key: ID!) { archiveProvider(key: $key) { provider { key } } }",
                   key: "google")["errors"]

    get "/connections/google/start"
    assert_response :not_found

    assert_nil ask("mutation On($key: ID!) { restoreProvider(key: $key) { provider { key } } }",
                   key: "google")["errors"]

    get "/connections/google/start"
    assert_response :redirect
  end

  test "adding, editing and archiving a provider are all written down" do
    add
    ask("mutation Edit($key: ID!, $name: String!) { updateProvider(key: $key, name: $name) { provider { key } } }",
        key: "google", name: "Workspace")
    ask("mutation Off($key: ID!) { archiveProvider(key: $key) { provider { key } } }", key: "google")

    actions = within(@tenant) do
      Event.where(action: [ Event::PROVIDER_CREATED, Event::PROVIDER_UPDATED, Event::PROVIDER_ARCHIVED ])
           .newest_first.map(&:action)
    end

    assert_equal [ Event::PROVIDER_ARCHIVED, Event::PROVIDER_UPDATED, Event::PROVIDER_CREATED ], actions

    assert_equal @admin.id, within(@tenant) { Event.where(action: Event::PROVIDER_CREATED).first.by_id }
  end
end
