require "test_helper"

class ManageApiTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def with_mailer(from: "masks@example.com")
    held = Rails.configuration.masks.mail_from
    Rails.configuration.masks.mail_from = from
    yield
  ensure
    Rails.configuration.masks.mail_from = held
  end

  setup do
    host! host_for(@tenant)

    @actor = create_actor(@tenant, scopes: "openid profile email masks:manage")
    @client = create_client(
      @tenant,
      allowed_scopes: "openid profile email masks:manage",
      approved_at: Time.current,
      grant_types: [ "authorization_code", "refresh_token" ]
    )
  end

  def resource
    @resource ||= issuer_for(@tenant).manage_resource
  end

  def bearer(scope: "openid masks:manage", for_resource: nil, actor: @actor)
    sign_in_as(actor)
    authorize(client_id: @client.client_id, scope: scope, resource: for_resource || resource)
    consent! if awaiting_consent?

    token(
      grant_type: "authorization_code",
      code: code_from,
      redirect_uri: OidcFlow::REDIRECT_URI,
      code_verifier: verifier,
      client_id: @client.client_id
    )["access_token"]
  end

  def ask(query, token, **variables)
    post "/manage/graphql",
         params: { query: query, variables: variables }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer #{token}"
         }

    JSON.parse(response.body)
  end

  test "the protected resource document names the scope and describes it" do
    get "/.well-known/oauth-protected-resource"

    body = JSON.parse(response.body)

    assert_response :success
    assert_equal resource, body["resource"]
    assert_equal [ origin_for(@tenant) ], body["authorization_servers"]
    assert_equal [ "masks:manage" ], body["scopes_supported"]
    assert_equal "Modify the masks backend", body.dig("scope_descriptions", "masks:manage")
  end

  test "the document is also served under the resource path, as RFC 9728 asks" do
    get "/.well-known/oauth-protected-resource/manage"

    assert_response :success
    assert_equal resource, JSON.parse(response.body)["resource"]
  end

  test "a bearer carrying masks:manage reaches the schema" do
    body = ask("{ viewer { nickname scopes } }", bearer)

    assert_response :success
    assert_equal @actor.nickname, body.dig("data", "viewer", "nickname")
    assert_includes body.dig("data", "viewer", "scopes"), "masks:manage"
  end

  test "no bearer at all is refused" do
    post "/manage/graphql", params: { query: "{ viewer { nickname } }" }.to_json,
                            headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :unauthorized
  end

  test "a token without masks:manage is refused with insufficient_scope, naming the scope" do
    held = bearer(scope: "openid profile")

    body = ask("{ viewer { nickname } }", held)

    assert_response :forbidden
    assert_equal "insufficient_scope", body["error"]
    assert_equal "masks:manage", body["scope"]
  end

  test "a token issued for another resource is refused" do
    held = bearer(for_resource: "https://things.example.com/api")

    ask("{ viewer { nickname } }", held)

    assert_response :unauthorized
  end

  test "an actor stripped of masks:manage cannot use a token that still carries it" do
    held = bearer

    within(@tenant) { @actor.update!(scopes: "openid profile email") }

    ask("{ viewer { nickname } }", held)

    assert_response :unauthorized
  end

  test "actors and clients are listed, and the tenant is readable" do
    body = ask("{ actors { nickname } clients { clientId } tenant { subdomain } }", bearer)

    assert_equal [ @actor.nickname ], body.dig("data", "actors").map { |a| a["nickname"] }
    assert_equal [ @client.client_id ], body.dig("data", "clients").map { |c| c["clientId"] }
    assert_equal @tenant.subdomain, body.dig("data", "tenant", "subdomain")
  end

  test "another tenant's actors are not visible" do
    create_actor(@other, nickname: "elsewhere")

    body = ask("{ actors { nickname } }", bearer)

    refute_includes body.dig("data", "actors").map { |a| a["nickname"] }, "elsewhere"
  end

  test "the ten profile claims that had no editor are writable" do
    body = ask(<<~GQL, bearer)
      mutation {
        updateActor(uuid: "#{@actor.uuid}", givenName: "Jon", locale: "en-CA", zoneinfo: "America/Vancouver") {
          actor { givenName locale zoneinfo }
        }
      }
    GQL

    assert_nil body["errors"]
    assert_equal "Jon", body.dig("data", "updateActor", "actor", "givenName")
    assert_equal "America/Vancouver", body.dig("data", "updateActor", "actor", "zoneinfo")
  end

  test "a profile field cleared to empty leaves the claim absent, not present and blank" do
    ask(%(mutation { updateActor(uuid: "#{@actor.uuid}", gender: "") { actor { gender } } }), bearer)

    actor = within(@tenant) { @actor.reload }

    assert_nil actor.gender
    refute_includes actor.claims("openid profile").keys, "gender"
  end

  test "changing an email takes its verification with it" do
    within(@tenant) { @actor.update!(email: "owner@example.invalid", email_verified_at: Time.current) }

    body = ask(<<~GQL, bearer)
      mutation {
        updateActor(uuid: "#{@actor.uuid}", email: "moved@example.invalid") {
          actor { email emailVerified }
        }
      }
    GQL

    assert_equal "moved@example.invalid", body.dig("data", "updateActor", "actor", "email")
    refute body.dig("data", "updateActor", "actor", "emailVerified")
  end

  test "required_scopes is writable, which nothing but the console could do" do
    body = ask(<<~GQL, bearer)
      mutation {
        updateClient(clientId: "#{@client.client_id}", requiredScopes: ["openid"]) {
          client { requiredScopes }
        }
      }
    GQL

    assert_equal [ "openid" ], body.dig("data", "updateClient", "client", "requiredScopes")
  end

  test "an admin cannot take masks:manage away from themselves" do
    body = ask(<<~GQL, bearer)
      mutation {
        setActorScopes(uuid: "#{@actor.uuid}", scopes: ["openid", "profile"]) {
          actor { scopes }
        }
      }
    GQL

    assert_match "cannot take masks:manage away from yourself", body["errors"].first["message"]
    assert_includes within(@tenant) { @actor.reload.scope_list }, "masks:manage"
  end

  test "an admin may grant masks:manage to somebody else" do
    second = create_actor(@tenant, nickname: "second")

    body = ask(<<~GQL, bearer)
      mutation {
        setActorScopes(uuid: "#{second.uuid}", scopes: ["openid", "masks:manage"]) {
          actor { scopes }
        }
      }
    GQL

    assert_includes body.dig("data", "setActorScopes", "actor", "scopes"), "masks:manage"
  end

  def admin
    @admin ||= bearer
  end

  def invite(nickname: "sam", email: "sam@example.com", scopes: nil)
    ask(<<~GQL, admin)
      mutation {
        inviteActor(
          nickname: "#{nickname}", email: "#{email}"
          #{scopes ? ", scopes: #{scopes.inspect}" : ''}
        ) {
          delivered url actor { uuid nickname activated emailVerified invitedAt }
        }
      }
    GQL
  end

  test "an admin invites somebody, and gets a link back when there is no mailer" do
    body = invite

    invited = body.dig("data", "inviteActor")

    assert_nil body["errors"]
    assert_equal false, invited["delivered"]
    assert_match %r{/invite/}, invited["url"]
    assert_equal false, invited.dig("actor", "activated")
    assert_not_nil invited.dig("actor", "invitedAt")
  end

  test "with a mailer configured the link is mailed and never handed to the admin" do
    with_mailer do
      body = invite

      invited = body.dig("data", "inviteActor")

      assert_equal true, invited["delivered"]
      assert_nil invited["url"]
      assert_equal 1, enqueued_jobs.count { |job| job[:args].first == "ActorMailer" }
    end
  end

  test "an invitation carries the scopes it names, the way setActorScopes does" do
    body = ask(<<~GQL, bearer)
      mutation {
        inviteActor(nickname: "sam", email: "sam@example.com", scopes: ["openid", "masks:manage"]) {
          actor { scopes }
        }
      }
    GQL

    assert_includes body.dig("data", "inviteActor", "actor", "scopes"), "masks:manage"
  end

  test "an invited nickname already in use is refused rather than duplicated" do
    invite

    assert_match(/nickname/i, invite["errors"].first["message"])
  end

  test "an invitation can be resent, and the admin cannot resend to somebody activated" do
    invited = invite.dig("data", "inviteActor", "actor", "uuid")

    resent = ask(<<~GQL, admin)
      mutation { resendInvitation(uuid: "#{invited}") { delivered url } }
    GQL

    assert_match %r{/invite/}, resent.dig("data", "resendInvitation", "url")

    refused = ask(<<~GQL, admin)
      mutation { resendInvitation(uuid: "#{@actor.uuid}") { delivered } }
    GQL

    assert_match(/already accepted/, refused["errors"].first["message"])
  end

  test "changing an address opens a confirmation for the new one" do
    with_mailer do
      body = ask(<<~GQL, admin)
        mutation {
          updateActor(uuid: "#{@actor.uuid}", email: "moved@example.invalid") {
            actor { email emailVerified }
          }
        }
      GQL

      assert_equal false, body.dig("data", "updateActor", "actor", "emailVerified")

      within(@tenant) do
        held = EmailVerification.where(actor_id: @actor.id).live.sole

        assert_equal "moved@example.invalid", held.address
        assert held.delivered?
      end
    end
  end

  test "an admin starts a password reset, and cannot start one for somebody invited" do
    started = ask(<<~GQL, admin)
      mutation { resetPassword(uuid: "#{@actor.uuid}") { delivered url } }
    GQL

    assert_match %r{/reset/}, started.dig("data", "resetPassword", "url")

    waiting = invite.dig("data", "inviteActor", "actor", "uuid")

    refused = ask(<<~GQL, admin)
      mutation { resetPassword(uuid: "#{waiting}") { delivered } }
    GQL

    assert_match(/has not accepted/, refused["errors"].first["message"])
  end

  test "backup codes are refused for an actor with no second factor" do
    body = ask(%(mutation { generateBackupCodes(uuid: "#{@actor.uuid}") { codes } }), bearer)

    assert_match "way past a second factor", body["errors"].first["message"]
  end

  test "backup codes are generated once an authenticator exists, retiring the rake task" do
    held = bearer
    enable_otp(@actor, @tenant)

    body = ask(%(mutation { generateBackupCodes(uuid: "#{@actor.uuid}") { codes actor { backupCodesRemaining } } }), held)

    assert_equal Actor::BACKUP_CODES, body.dig("data", "generateBackupCodes", "codes").length
    assert_equal Actor::BACKUP_CODES, body.dig("data", "generateBackupCodes", "actor", "backupCodesRemaining")
  end

  test "the admin API cannot hand a masks: scope to a client nobody approved" do
    dynamic = create_client(@tenant, name: "Dynamic", dynamic: true)

    body = ask(<<~GQL, bearer)
      mutation {
        updateClient(clientId: "#{dynamic.client_id}", allowedScopes: ["openid", "masks:manage"]) {
          client { allowedScopes }
        }
      }
    GQL

    assert_match "may only be granted to an approved client", body["errors"].first["message"]
    assert_empty within(@tenant) { Scopes.reserved(dynamic.reload.scope_list) }
  end

  test "the ceiling offered to dynamic registration cannot include a masks: scope" do
    body = ask(<<~GQL, bearer)
      mutation {
        updateTenant(dynamicClientScopes: ["openid", "masks:manage"]) { tenant { dynamicClientScopes } }
      }
    GQL

    assert_match "may not be offered to dynamic registration", body["errors"].first["message"]
  end

  test "archiving the client you are signed in with is refused" do
    body = ask(%(mutation { archiveClient(clientId: "#{@client.client_id}") { client { archivedAt } } }), bearer)

    assert_match "would lock you out", body["errors"].first["message"]
    assert_nil within(@tenant) { @client.reload.archived_at }
  end

  test "a public client has no secret to rotate" do
    body = ask(%(mutation { rotateClientSecret(clientId: "#{@client.client_id}") { secret } }), bearer)

    assert_match "public client has no secret", body["errors"].first["message"]
  end

  test "a session can be listed and revoked" do
    held = bearer

    listed = ask("{ sessions { id actor { nickname } } }", held)
    id = listed.dig("data", "sessions").first["id"]

    revoked = ask(%(mutation { revokeSession(id: "#{id}") { session { revokedAt } } }), held)

    assert_not_nil revoked.dig("data", "revokeSession", "session", "revokedAt")
  end

  test "a device is listed with who signed in from it, and blocking it shuts that browser out" do
    held = bearer

    listed = ask("{ devices { id label category known actors { nickname } } }", held)
    device = listed.dig("data", "devices").first

    assert_not_nil device
    assert_equal [ @actor.nickname ], device["actors"].map { |one| one["nickname"] }

    blocked = ask(%(mutation { blockDevice(id: "#{device['id']}") { device { blockedAt } } }), held)

    assert_not_nil blocked.dig("data", "blockDevice", "device", "blockedAt")
    assert_empty within(@tenant) { Session.live.where(actor: @actor).to_a }

    post "/manage/graphql",
         params: { query: "{ viewer { nickname } }" }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer #{held}"
         }

    assert_response :forbidden
  end

  test "signing a device out from the admin API revokes the sessions and tokens it holds" do
    held = bearer

    id = ask("{ devices { id sessions { id } } }", held).dig("data", "devices").first["id"]

    ask(%(mutation { signOutDevice(id: "#{id}") { device { id } } }), held)

    assert_empty within(@tenant) { Session.live.where(actor: @actor).to_a }
    assert_empty within(@tenant) { AccessToken.live.where(actor: @actor).to_a }
  end

  test "the schema refuses a query past its token ceiling" do
    huge = "{ #{Array.new(2000) { |i| "a#{i}: viewer { nickname }" }.join(' ')} }"

    body = ask(huge, bearer)

    assert body["errors"].any?, "a #{huge.length}-character query was accepted"
    assert_nil body["data"], "the ceiling refused the query but something still executed"
    assert_match(/too large|token/i, body["errors"].first["message"])
  end

  test "the ceiling is not so low that an ordinary admin query trips it" do
    body = ask(
      "{ viewer { nickname } tenant { subdomain signingKeys { kid } } " \
      "actors { uuid nickname email scopes } clients { clientId allowedScopes } " \
      "sessions { id actor { nickname } } scopesSupported }",
      bearer
    )

    assert_nil body["errors"], body["errors"].to_s
  end

  test "the admin page is served for any path under /manage, so the SPA can route" do
    get "/manage"
    assert_response :success
    assert_match "id=\"manage\"", response.body

    get "/manage/clients/whatever"
    assert_response :success

    boot = JSON.parse(CGI.unescapeHTML(response.body[/data-boot="([^"]*)"/, 1]))

    assert_equal issuer_for(@tenant).manage_resource, boot["resource"]
    assert_equal origin_for(@tenant), boot["issuer"]
    assert_equal "/manage/graphql", boot["graphql"]
  end

  test "the admin page itself is public, and carries no token" do
    get "/manage"

    refute_match "masks_session", response.body
    refute_match "access_token", response.body
  end

  test "the tally counts everything, not just the page of records a list query returns" do
    crowd = Manage::Types::QueryType::LIMIT + 3

    within(@tenant) { crowd.times { |at| create_actor(@tenant, nickname: "extra#{at}") } }

    token = bearer
    answer = ask("query { actors { uuid } tally { actors clients sessions devices } }", token)

    listed = answer["data"]["actors"].length
    counted = answer["data"]["tally"]["actors"]

    assert_equal Manage::Types::QueryType::LIMIT, listed
    assert_operator counted, :>, listed
    assert_equal within(@tenant) { Actor.count }, counted
  end

  test "activity buckets sign-ins by day and leaves quiet days in the series at zero" do
    token = bearer

    within(@tenant) do
      Session.where.not(id: nil).update_all(authenticated_at: 2.days.ago)
    end

    days = ask("query { activity(days: 7) { date signIns } }", token)["data"]["activity"]

    assert_equal 7, days.length
    assert_equal days.map { |one| one["date"] }.sort, days.map { |one| one["date"] }
    assert_equal Date.current.to_s, days.last["date"]
    assert_operator days.sum { |one| one["signIns"] }, :>, 0
    assert days.any? { |one| one["signIns"].zero? }
  end

  test "activity refuses to reach further back than its ceiling" do
    token = bearer
    longest = Manage::Types::QueryType::LONGEST

    days = ask("query { activity(days: 5000) { date } }", token)["data"]["activity"]

    assert_equal longest, days.length
  end
end
