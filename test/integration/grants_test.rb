require "test_helper"

class GrantsTest < ActionDispatch::IntegrationTest
  setup do
    @actor = create_actor(@tenant, nickname: "ada", email: "ada@example.com")
    @client = create_client(@tenant, name: "Probe")
    host! host_for(@tenant)
  end

  def consent!(scopes: "openid profile", audience: [])
    within(@tenant) do
      Consent.record!(actor: @actor, client: @client, scopes: scopes, audience: audience)
    end
  end

  def provider!(key: "acme")
    within(@tenant) do
      Provider.create!(
        key: key, name: key.capitalize,
        authorization_url: "https://#{key}.test/authorize",
        token_url: "https://#{key}.test/token",
        client_id: "upstream"
      )
    end
  end

  def connection!(provider, subject: "upstream-1")
    within(@tenant) do
      Connection.create!(
        provider: provider, actor: @actor, subject: subject,
        label: "ada@#{provider.key}.test", connected_at: Time.current
      )
    end
  end

  def refresh_token!
    within(@tenant) do
      RefreshToken.mint!(
        actor: @actor, client: @client, scopes: "openid",
        expires_at: 30.days.from_now
      )
    end
  end

  test "the console lists what a person has allowed in and what they have connected" do
    consent!
    connection!(provider!)

    data = manage(
      "query Actor($uuid: ID!) {
        actor(uuid: $uuid) {
          consents { id scopes client { clientId name } }
          connections { id label signedInAt provider { key name releaseScope } }
        }
      }",
      uuid: @actor.uuid
    )

    held = data["data"]["actor"]

    assert_equal [ "Probe" ], held["consents"].map { |one| one["client"]["name"] }
    assert_equal [ "openid", "profile" ], held["consents"].first["scopes"]
    assert_equal [ "Acme" ], held["connections"].map { |one| one["provider"]["name"] }
    assert_equal "masks:connections:acme", held["connections"].first["provider"]["releaseScope"]
  end

  test "cutting a client off revokes its refresh tokens as well as the consent" do
    consent = consent!
    token = refresh_token!

    data = manage(
      "mutation Cut($id: ID!) { revokeConsent(id: $id) { consent { revokedAt } } }",
      id: consent.id
    )

    assert data["data"]["revokeConsent"]["consent"]["revokedAt"].present?

    within(@tenant) do
      assert consent.reload.revoked_at.present?
      assert token.reload.consumed_at.present?
      assert Event.exists?(action: Event::CONSENT_REVOKED)
    end
  end

  test "the console disconnects an upstream account" do
    connection = connection!(provider!)

    manage(
      "mutation Cut($id: ID!) { revokeConnection(id: $id) { connection { revokedAt } } }",
      id: connection.uuid
    )

    within(@tenant) do
      assert connection.reload.revoked_at.present?
      assert_match "revoked by", connection.revoked_reason
      assert Event.exists?(action: Event::CONNECTION_UNLINKED)
    end
  end

  test "a client shows who has allowed it in" do
    consent!

    data = manage(
      "query Client($clientId: ID!) {
        client(clientId: $clientId) { consents { id actor { nickname } } }
      }",
      clientId: @client.client_id
    )

    assert_equal [ "ada" ], data["data"]["client"]["consents"].map { |one| one["actor"]["nickname"] }
  end

  test "connections filter by provider and by person" do
    first = provider!(key: "acme")
    second = provider!(key: "beta")

    connection!(first, subject: "one")
    connection!(second, subject: "two")

    data = manage(
      'query { connections(provider: "acme") { id provider { key } } }'
    )

    assert_equal [ "acme" ], data["data"]["connections"].map { |one| one["provider"]["key"] }

    missing = manage('query { connections(actor: "not-a-uuid") { id } }')

    assert_empty missing["data"]["connections"]
  end

  test "the console lists the tokens a person is holding" do
    refresh = refresh_token!

    data = manage(
      "query Held($uuid: ID!, $clientId: ID!) {
        tokens(actor: $uuid, client: $clientId) { id kind scopes client { name } }
        actor(uuid: $uuid) { tokens { id } }
      }",
      uuid: @actor.uuid, clientId: @client.client_id
    )

    held = data["data"]["tokens"]

    assert_equal [ refresh.id.to_s ], held.map { |one| one["id"] }
    assert_equal "refresh", held.first["kind"]
    assert_equal "Probe", held.first["client"]["name"]

    assert_includes data["data"]["actor"]["tokens"].map { |one| one["id"] }, refresh.id.to_s
  end

  test "invitations and resets are never handed out as tokens" do
    refresh = refresh_token!

    invitation = within(@tenant) do
      PasswordReset.mint!(actor: @actor, expires_at: 1.hour.from_now)
    end

    data = manage("query { tokens { id kind } }")
    held = data["data"]["tokens"].map { |one| one["id"] }

    assert_includes held, refresh.id.to_s
    assert_not_includes held, invitation.id.to_s
  end

  test "a reset token cannot be revoked through the token surface" do
    reset = within(@tenant) { PasswordReset.mint!(actor: @actor, expires_at: 1.hour.from_now) }

    post "/manage/graphql",
         params: {
           query: "mutation Cut($id: ID!) { revokeToken(id: $id) { revoked } }",
           variables: { id: reset.id }
         }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer #{manage_token}"
         }

    body = JSON.parse(response.body)

    assert_match(/no token with that id/, body["errors"].to_s)
    assert_nil within(@tenant) { reset.reload.consumed_at }
  end

  test "revoking a refresh chain ends everything exchanged along it" do
    root = refresh_token!

    rotated = within(@tenant) do
      RefreshToken.mint!(
        actor: @actor, client: @client, scopes: "openid",
        parent: root, expires_at: 30.days.from_now
      )
    end

    access = within(@tenant) do
      AccessToken.mint!(
        actor: @actor, client: @client, scopes: "openid",
        parent: rotated, expires_at: 1.hour.from_now
      )
    end

    data = manage(
      "mutation Cut($id: ID!) { revokeToken(id: $id, family: true) { revoked } }",
      id: rotated.id
    )

    assert_equal 3, data["data"]["revokeToken"]["revoked"]

    within(@tenant) do
      assert root.reload.consumed_at.present?
      assert rotated.reload.consumed_at.present?
      assert access.reload.consumed_at.present?
      assert Event.exists?(action: Event::TOKEN_REVOKED)
    end
  end

  test "revoking one token leaves the rest of the chain alone" do
    root = refresh_token!
    other = refresh_token!

    manage("mutation Cut($id: ID!) { revokeToken(id: $id) { revoked } }", id: root.id)

    within(@tenant) do
      assert root.reload.consumed_at.present?
      assert_nil other.reload.consumed_at
    end
  end

  test "tokens filter by kind, and an unknown kind is refused" do
    refresh = refresh_token!

    data = manage('query { tokens(kind: "access") { id kind } }')
    held = data["data"]["tokens"]

    assert_not_empty held
    assert_equal [ "access" ], held.map { |one| one["kind"] }.uniq
    assert_not_includes held.map { |one| one["id"] }, refresh.id.to_s

    post "/manage/graphql",
         params: { query: 'query { tokens(kind: "nonsense") { id } }' }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer #{manage_token}"
         }

    assert_match(/no token kind called nonsense/, JSON.parse(response.body)["errors"].to_s)
  end

  test "a client shows what it is holding" do
    refresh_token!

    data = manage(
      "query Client($clientId: ID!) {
        client(clientId: $clientId) { tokens { id kind actor { nickname } } }
      }",
      clientId: @client.client_id
    )

    held = data["data"]["client"]["tokens"]

    assert_equal [ "ada" ], held.map { |one| one["actor"]["nickname"] }
    assert_equal [ "refresh" ], held.map { |one| one["kind"] }
  end

  test "somebody cuts an application off from their own account page" do
    consent = consent!
    token = refresh_token!

    sign_in_as(@actor)
    delete "/account/consents/#{consent.id}"

    assert_redirected_to root_path

    within(@tenant) do
      assert consent.reload.revoked_at.present?
      assert token.reload.consumed_at.present?
    end
  end

  test "somebody disconnects an upstream account from their own account page" do
    connection = connection!(provider!)

    sign_in_as(@actor)
    delete "/account/connections/#{connection.uuid}"

    assert_redirected_to root_path
    assert within(@tenant) { connection.reload.revoked_at.present? }
  end

  test "the json api that clients use still answers with json" do
    connection = connection!(provider!)

    sign_in_as(@actor)
    delete "/connections/#{connection.uuid}"

    assert_response :success
    assert_equal connection.uuid, JSON.parse(response.body)["id"]
  end

  test "nobody disconnects an upstream account on somebody else's page" do
    connection = connection!(provider!)
    intruder = create_actor(@tenant, nickname: "eve", email: "eve@example.com")

    sign_in_as(intruder)
    delete "/account/connections/#{connection.uuid}"

    assert_redirected_to root_path
    assert_nil within(@tenant) { connection.reload.revoked_at }
  end

  test "nobody cuts off an application on somebody else's account" do
    consent = consent!
    intruder = create_actor(@tenant, nickname: "eve", email: "eve@example.com")

    sign_in_as(intruder)
    delete "/account/consents/#{consent.id}"

    assert_redirected_to root_path
    assert_nil within(@tenant) { consent.reload.revoked_at }
  end

  test "the account page lists connections and offers the rest" do
    connection!(provider!(key: "acme"))
    provider!(key: "beta")

    sign_in_as(@actor)
    get "/"

    assert_response :success
    assert_match "Acme", response.body
    assert_match "Connect Beta", response.body
    assert_match "Disconnect", response.body
  end

  private

    def manage(query, **variables)
      post "/manage/graphql",
           params: { query: query, variables: variables }.to_json,
           headers: {
             "CONTENT_TYPE" => "application/json",
             "HTTP_AUTHORIZATION" => "Bearer #{manage_token}"
           }

      JSON.parse(response.body).tap do |body|
        assert_nil body["errors"], body["errors"].to_s
      end
    end

    def manage_token
      @manage_token ||= begin
        console = create_client(
          @tenant,
          name: "Console",
          allowed_scopes: "openid #{Scopes::MANAGE}",
          approved_at: Time.current,
          grant_types: [ "authorization_code", "refresh_token" ]
        )

        within(@tenant) { @actor.update!(scopes: "openid profile email #{Scopes::MANAGE}") }

        sign_in_as(@actor)
        authorize(
          client_id: console.client_id,
          scope: "openid #{Scopes::MANAGE}",
          resource: issuer_for(@tenant).manage_resource
        )
        consent! if awaiting_consent?

        issued = token(
          grant_type: "authorization_code",
          code: code_from,
          redirect_uri: OidcFlow::REDIRECT_URI,
          code_verifier: verifier,
          client_id: console.client_id
        )

        reset!
        host! host_for(@tenant)

        issued["access_token"]
      end
    end
end
