require "test_helper"
require_relative "../support/upstream"

class DelegationTest < ActionDispatch::IntegrationTest
  include Federated
  include OidcFlow

  UPSTREAM = Exchange::UPSTREAM_ACCESS_TOKEN
  SCOPE = "openid offline_access masks:delegate:acme".freeze

  setup do
    @actor = create_actor(@tenant, nickname: "owner", email: "owner@acme.test")
    @client = create_client(
      name: "Uris", token_endpoint_auth_method: "client_secret_post", approved_at: Time.current,
      allowed_scopes: "openid profile email offline_access masks:delegate:",
      grant_types: [ "authorization_code", "refresh_token", Exchange::GRANT_TYPE ]
    )
    @secret = within(@tenant) { @client.issue_secret!.tap { @client.save! } }
    @issued = 0

    @upstream.route("/o/token") do
      @issued += 1
      { "access_token" => "upstream-access-#{@issued}", "refresh_token" => "upstream-refresh-#{@issued}",
        "expires_in" => 3600, "id_token" => @upstream.id_token_for(@upstream.claims) }
    end
  end

  def delegating!(**attributes)
    create_provider(delegates: true, delegated_scopes: "files.read",
                    delegation_params: { "access_type" => "offline" }, **attributes)
  end

  def connect!(sub: "acme-1", scope: SCOPE, key: "acme", **params)
    authorize(client_id: @client.client_id, scope: scope, **params)
    consent! if awaiting_consent?

    return response unless response.redirect? && response.location.start_with?(@upstream.url)

    handoff = Rack::Utils.parse_query(URI.parse(response.location).query)
    @upstream.announce("sub" => sub, "email" => "grace@acme.test", "email_verified" => true, "nonce" => handoff["nonce"])

    get "/login/provider/#{key}/callback", params: { code: "upstream-code", state: handoff["state"] }
    follow_redirect! while response.redirect? && URI.parse(response.location).host.to_s.end_with?(".auth.test")

    response
  end

  def mcp_server!
    @upstream.route("/.well-known/oauth-protected-resource/mcp",
                    "resource" => @upstream.url("/mcp"), "authorization_servers" => [ @upstream.url ])
    @upstream.route("/.well-known/oauth-authorization-server",
                    "issuer" => @upstream.url,
                    "authorization_endpoint" => @upstream.url("/mcp/authorize"),
                    "token_endpoint" => @upstream.url("/mcp/token"),
                    "registration_endpoint" => @upstream.url("/mcp/register"),
                    "code_challenge_methods_supported" => [ "S256" ],
                    "token_endpoint_auth_methods_supported" => [ "none" ])
    @upstream.route("/mcp/register", "client_id" => "registered-by-masks")
    @upstream.route("/mcp/token", "access_token" => "mcp-access", "refresh_token" => "mcp-refresh", "expires_in" => 3600)

    within(@tenant) do
      Provider.new(key: "notion", name: "Notion", protocol: "mcp", resource_url: @upstream.url("/mcp")).tap do |provider|
        provider.register!(callback: "#{origin_for(@tenant)}/login/provider/notion/callback")
        provider.save!
      end
    end
  end

  def redeem!(code = code_from)
    token(grant_type: "authorization_code", code: code, redirect_uri: REDIRECT_URI, code_verifier: verifier,
          client_id: @client.client_id, client_secret: @secret)
  end

  def release(access_token, connection:, client_id: @client.client_id, client_secret: @secret, **params)
    token(grant_type: Exchange::GRANT_TYPE, subject_token: access_token, subject_token_type: Exchange::ACCESS_TOKEN,
          requested_token_type: UPSTREAM, audience: connection, client_id: client_id, client_secret: client_secret, **params)
  end

  def delegated!
    delegating!
    sign_in_as(@actor)
    connect!

    redeem!
  end

  def events(action)
    within(@tenant) { Event.where(action: action).to_a }
  end

  test "somebody lets an application use their account elsewhere, and it is released to that application" do
    delegating!
    sign_in_as(@actor)

    authorize(client_id: @client.client_id, scope: SCOPE)

    assert awaiting_consent?
    assert_includes auth_data.dig("consent", "scopes").map(&:first), "masks:delegate:acme"

    consent!

    assert response.redirect?
    upstream = Rack::Utils.parse_query(URI.parse(response.location).query)

    assert response.location.start_with?(@upstream.url("/o/authorize"))
    assert_includes upstream["scope"].split, "files.read"
    assert_equal "offline", upstream["access_type"]

    @upstream.announce("sub" => "acme-1", "email" => "grace@acme.test", "email_verified" => true, "nonce" => upstream["nonce"])
    get "/login/provider/acme/callback", params: { code: "upstream-code", state: upstream["state"] }
    follow_redirect!

    assert code_from, response.location

    body = redeem!
    held = body["delegations"].sole

    assert body["refresh_token"]
    assert_equal "acme", held["provider"]

    connection = within(@tenant) { Connection.find_by!(uuid: held["connection"]) }

    assert_equal @actor.id, connection.actor_id
    assert_equal "acme-1", connection.subject

    released = release(body["access_token"], connection: held["connection"])

    assert_equal "upstream-access-1", released["access_token"], released.inspect
    assert_equal UPSTREAM, released["issued_token_type"]
    assert_operator released["expires_in"], :>, 3000
    assert_equal 1, events(Event::DELEGATION_GRANTED).size
    assert_equal 1, events(Event::DELEGATION_RELEASED).size
  end

  test "the upstream token is kept encrypted" do
    delegated!

    raw = within(@tenant) { Connection.connection.select_value("SELECT access_token FROM connections LIMIT 1") }

    assert raw.present?
    assert_not_includes raw, "upstream-access"
  end

  test "an application with the delegation already in hand is not asked again" do
    delegated!

    authorize(client_id: @client.client_id, scope: SCOPE, state: "again")

    assert code_from, [ response.status, response.location, auth_data&.slice("prompt", "consent") ].inspect
    assert_equal 1, within(@tenant) { Delegation.live.count }
  end

  test "an expiring upstream token is refreshed by masks, and a rotated refresh token is kept" do
    body = delegated!
    connection = body["delegations"].sole["connection"]

    within(@tenant) { Connection.find_by!(uuid: connection).update!(access_token_expires_at: 10.seconds.from_now) }

    released = release(body["access_token"], connection: connection)

    assert_equal "upstream-access-2", released["access_token"]
    assert_equal "upstream-refresh-1", @upstream.bodies_for("/o/token").last["refresh_token"]
    assert_equal "refresh_token", @upstream.bodies_for("/o/token").last["grant_type"]
    assert_equal "upstream-refresh-2", within(@tenant) { Connection.find_by!(uuid: connection).refresh_token }
  end

  test "a refresh the provider refuses forgets the tokens and says to connect again" do
    body = delegated!
    connection = body["delegations"].sole["connection"]

    within(@tenant) { Connection.find_by!(uuid: connection).update!(access_token_expires_at: 1.minute.ago) }
    @upstream.route("/o/token") { nil }

    released = release(body["access_token"], connection: connection)

    assert_response :bad_request
    assert_equal "invalid_grant", released["error"]
    assert_nil within(@tenant) { Connection.find_by!(uuid: connection).refresh_token }
    assert_equal 1, events(Event::DELEGATION_REFUSED).size
  end

  test "a provider that does not answer is worth retrying, and nothing is forgotten" do
    body = delegated!
    connection = body["delegations"].sole["connection"]

    within(@tenant) do
      Connection.find_by!(uuid: connection).update!(access_token_expires_at: 1.minute.ago)
      Provider.find_by!(key: "acme").update!(token_url: "http://127.0.0.1:1/token")
    end

    released = release(body["access_token"], connection: connection)

    assert_response :service_unavailable
    assert_equal "temporarily_unavailable", released["error"]
    assert within(@tenant) { Connection.find_by!(uuid: connection).refresh_token }
  end

  test "a masks refresh token keeps releasing after the access token it came with is gone" do
    body = delegated!
    connection = body["delegations"].sole["connection"]

    refreshed = token(grant_type: "refresh_token", refresh_token: body["refresh_token"],
                      client_id: @client.client_id, client_secret: @secret)

    assert_equal connection, refreshed["delegations"].sole["connection"]
    assert_equal "upstream-access-1", release(refreshed["access_token"], connection: connection)["access_token"]
  end

  test "another client cannot spend somebody's token to reach their account" do
    body = delegated!
    other = create_client(name: "Other", token_endpoint_auth_method: "client_secret_post", approved_at: Time.current,
                          allowed_scopes: "openid masks:delegate:", grant_types: [ Exchange::GRANT_TYPE ])
    other_secret = within(@tenant) { other.issue_secret!.tap { other.save! } }

    released = release(body["access_token"], connection: body["delegations"].sole["connection"],
                                             client_id: other.client_id, client_secret: other_secret)

    assert_equal "invalid_grant", released["error"]
    assert_nil released["access_token"]
  end

  test "a token without the delegation scope releases nothing" do
    body = delegated!
    connection = body["delegations"].sole["connection"]

    narrowed = token(grant_type: "refresh_token", refresh_token: body["refresh_token"], scope: "openid",
                     client_id: @client.client_id, client_secret: @secret)

    released = release(narrowed["access_token"], connection: connection)

    assert_equal "insufficient_scope", released["error"]
  end

  test "somebody else's connection is not released, even to the same application" do
    body = delegated!
    stranger = create_actor(@tenant, nickname: "stranger")
    theirs = within(@tenant) do
      Connection.record!(provider: Provider.find_by!(key: "acme"), actor: stranger, identity: { "sub" => "acme-2" })
    end

    released = release(body["access_token"], connection: theirs.uuid)

    assert_equal "invalid_grant", released["error"]
  end

  test "an upstream token is never asked for with scope, resource or lifetime" do
    body = delegated!

    released = release(body["access_token"], connection: body["delegations"].sole["connection"], scope: "openid")

    assert_equal "invalid_request", released["error"]
  end

  test "stopping a delegation from the account page ends the release and asks again next time" do
    body = delegated!
    connection = body["delegations"].sole["connection"]
    delegation = within(@tenant) { Delegation.live.sole }

    get "/"

    assert_includes response.body, "Uris can use it"

    delete "/account/delegations/#{delegation.uuid}"

    assert within(@tenant) { delegation.reload.revoked? }
    assert_equal "invalid_grant", release(body["access_token"], connection: connection)["error"]
    assert_equal "invalid_grant", token(grant_type: "refresh_token", refresh_token: body["refresh_token"],
                                        client_id: @client.client_id, client_secret: @secret)["error"]

    authorize(client_id: @client.client_id, scope: SCOPE, state: "again")

    assert awaiting_consent?
  end

  test "disconnecting the account ends every delegation made from it" do
    body = delegated!
    connection = body["delegations"].sole["connection"]

    delete "/account/connections/#{connection}"

    assert within(@tenant) { Delegation.sole.revoked? }
    assert_nil within(@tenant) { Connection.find_by!(uuid: connection).access_token }
    assert_equal "invalid_grant", release(body["access_token"], connection: connection)["error"]
  end

  test "revoking an application's access ends its delegations" do
    body = delegated!

    delete "/account/apps/#{@client.client_id}"

    assert within(@tenant) { Delegation.sole.revoked? }
    assert_equal "invalid_grant", release(body["access_token"], connection: body["delegations"].sole["connection"])["error"]
  end

  test "a client nobody approved is not trusted with anybody's account" do
    delegating!
    within(@tenant) { @client.update!(approved_at: nil) }
    sign_in_as(@actor)

    authorize(client_id: @client.client_id, scope: SCOPE)

    assert_equal "unauthorized_client", redirected["error"]
  end

  test "a different account than the one already connected is refused" do
    delegating!
    within(@tenant) do
      Connection.record!(provider: Provider.find_by!(key: "acme"), actor: @actor, identity: { "sub" => "acme-1" })
    end
    sign_in_as(@actor)

    connect!(sub: "acme-somebody-else")

    assert_equal "access_denied", redirected["error"]
    assert_equal 0, within(@tenant) { Delegation.count }
  end

  test "an account already connected to somebody else is refused" do
    delegating!
    stranger = create_actor(@tenant, nickname: "stranger")
    within(@tenant) do
      Connection.record!(provider: Provider.find_by!(key: "acme"), actor: stranger, identity: { "sub" => "acme-1" })
    end
    sign_in_as(@actor)

    connect!

    assert_equal "access_denied", redirected["error"]
    assert_equal stranger.id, within(@tenant) { Connection.find_by!(subject: "acme-1").actor_id }
  end

  test "connecting a new account asks for a recent sign-in" do
    delegating!
    sign_in_as(@actor)

    travel 20.minutes do
      connect!
    end

    assert_equal "login_required", redirected["error"]
    assert_equal 0, within(@tenant) { Connection.count }
  end

  test "an application cannot connect somebody's account without asking them" do
    delegating!
    sign_in_as(@actor)

    authorize(client_id: @client.client_id, scope: SCOPE, prompt: "none")

    assert_equal "interaction_required", redirected["error"]
  end

  test "a provider that does not delegate cannot be asked for" do
    create_provider
    sign_in_as(@actor)

    authorize(client_id: @client.client_id, scope: SCOPE)

    assert_equal "invalid_scope", redirected["error"]
  end

  test "somebody who declines at the provider sends the application an error" do
    delegating!
    sign_in_as(@actor)

    authorize(client_id: @client.client_id, scope: SCOPE)
    consent!
    handoff = Rack::Utils.parse_query(URI.parse(response.location).query)

    get "/login/provider/acme/callback", params: { error: "access_denied", state: handoff["state"] }
    follow_redirect! while response.redirect? && URI.parse(response.location).host.to_s.end_with?(".auth.test")

    assert_equal "access_denied", redirected["error"]
    assert_equal 0, within(@tenant) { Delegation.count }
  end

  test "a provider whose scopes change needs connecting again" do
    delegated!

    within(@tenant) { Provider.find_by!(key: "acme").update!(delegated_scopes: "files.read files.write") }

    authorize(client_id: @client.client_id, scope: SCOPE, state: "again")

    assert awaiting_consent?
  end

  test "an MCP server's own authorization server is found, registered with, and delegated through" do
    provider = mcp_server!

    assert_equal "registered-by-masks", provider.client_id
    assert_equal Provider::PUBLIC, provider.token_auth_method
    assert provider.delegates?
    assert_not provider.signs_in?

    sign_in_as(@actor)
    authorize(client_id: @client.client_id, scope: "openid offline_access masks:delegate:notion")
    consent!

    handoff = Rack::Utils.parse_query(URI.parse(response.location).query)

    assert response.location.start_with?(@upstream.url("/mcp/authorize"))
    assert_equal @upstream.url("/mcp"), handoff["resource"]
    assert_equal "registered-by-masks", handoff["client_id"]

    get "/login/provider/notion/callback", params: { code: "mcp-code", state: handoff["state"] }
    follow_redirect! while response.redirect? && URI.parse(response.location).host.to_s.end_with?(".auth.test")

    body = redeem!
    held = body["delegations"].sole

    assert_equal "notion", held["provider"]
    assert_equal "masks:#{@actor.uuid}", within(@tenant) { Connection.find_by!(uuid: held["connection"]).subject }
    assert_equal "mcp-access", release(body["access_token"], connection: held["connection"])["access_token"]

    redeemed = @upstream.bodies_for("/mcp/token").last

    assert_equal @upstream.url("/mcp"), redeemed["resource"]
    assert_equal "registered-by-masks", redeemed["client_id"]
    assert_nil redeemed["client_secret"]
  end

  test "an MCP server that takes a client secret is registered with one, and sends it" do
    @upstream.route("/.well-known/oauth-protected-resource/mcp", "authorization_servers" => [ @upstream.url ])
    @upstream.route("/.well-known/oauth-authorization-server",
                    "issuer" => @upstream.url, "authorization_endpoint" => @upstream.url("/mcp/authorize"),
                    "token_endpoint" => @upstream.url("/mcp/token"), "registration_endpoint" => @upstream.url("/mcp/register"),
                    "code_challenge_methods_supported" => %w[plain S256],
                    "token_endpoint_auth_methods_supported" => %w[client_secret_basic client_secret_post none])
    @upstream.route("/mcp/register", "client_id" => "confidential", "client_secret" => "kept-by-masks",
                                     "token_endpoint_auth_method" => "client_secret_basic")

    provider = within(@tenant) do
      Provider.new(key: "notion", name: "Notion", protocol: "mcp", resource_url: @upstream.url("/mcp")).tap do |held|
        held.register!(callback: "https://example.test/cb")
        held.save!
      end
    end

    assert_equal "client_secret_basic", provider.token_auth_method
    assert_equal "kept-by-masks", within(@tenant) { provider.reload.client_secret }
  end

  test "an MCP provider never signs anybody in" do
    mcp_server!

    assert_not within(@tenant) { Provider.signing_in.exists?(key: "notion") }
  end

  test "a server that publishes no protected resource metadata cannot be registered with" do
    provider = within(@tenant) { Provider.new(key: "nothing", name: "Nothing", protocol: "mcp", resource_url: @upstream.url("/elsewhere")) }

    error = assert_raises(Provider::Untrusted) { provider.register!(callback: "https://example.test/cb") }

    assert_match(/protected resource metadata/, error.message)
  end

  test "an authorization server without PKCE is not registered with" do
    @upstream.route("/.well-known/oauth-protected-resource/mcp", "authorization_servers" => [ @upstream.url ])
    @upstream.route("/.well-known/oauth-authorization-server",
                    "issuer" => @upstream.url, "authorization_endpoint" => @upstream.url("/a"),
                    "token_endpoint" => @upstream.url("/t"), "registration_endpoint" => @upstream.url("/r"))

    provider = within(@tenant) { Provider.new(key: "nopkce", name: "No PKCE", protocol: "mcp", resource_url: @upstream.url("/mcp")) }

    assert_raises(Provider::Untrusted) { provider.register!(callback: "https://example.test/cb") }
  end

  test "a person or an application with delegations can still be deleted" do
    delegated!

    within(@tenant) do
      @client.reload.destroy!
      @actor.reload.destroy!
    end

    assert_equal 0, within(@tenant) { Delegation.count }
  end

  test "a handshake that asks for delegation may exchange" do
    handshake = Handshake.new(name: "Uris", redirect_uris: [ REDIRECT_URI ], resource: "https://uris.test",
                              scopes: "openid masks:delegate:acme")

    assert_includes handshake.grant_types, Exchange::GRANT_TYPE
    assert_not_includes Handshake.new(scopes: "openid").grant_types, Exchange::GRANT_TYPE
  end
end
