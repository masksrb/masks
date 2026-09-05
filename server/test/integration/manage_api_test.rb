require "test_helper"
require "vips"

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
        updateActor(uuid: "#{@actor.uuid}", givenName: "Ada", locale: "en-CA", zoneinfo: "America/Vancouver") {
          actor { givenName locale zoneinfo }
        }
      }
    GQL

    assert_nil body["errors"]
    assert_equal "Ada", body.dig("data", "updateActor", "actor", "givenName")
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

  test "an actor carries their own sessions and devices, so one query draws the page" do
    body = ask(<<~GQL, bearer)
      query {
        actors {
          uuid nickname
          sessions { id ipAddress authenticatedAt expiresAt }
          devices { id label blockedAt }
        }
        viewer { uuid }
        scopesSupported
      }
    GQL

    assert_nil body["errors"], body["errors"].to_s

    person = body.dig("data", "actors").sole

    assert_equal @actor.uuid, person["uuid"]
    assert_equal 1, person["sessions"].length
    assert_equal 1, person["devices"].length
    assert_equal @actor.uuid, body.dig("data", "viewer", "uuid")
  end

  test "an actor's sessions are the live ones, and revoking one drops it from them" do
    held = bearer

    id = ask("{ actors { sessions { id } } }", held).dig("data", "actors").sole["sessions"].sole["id"]

    ask(%(mutation { revokeSession(id: "#{id}") { session { revokedAt } } }), held)

    assert_empty ask("{ actors { sessions { id } } }", held).dig("data", "actors").sole["sessions"]
  end

  test "devices nobody signed in on are askable on their own, so they stay blockable" do
    held = bearer

    within(@tenant) { ::Device.identify(nil, user_agent: "curl/8", ip_address: "10.0.0.9") }

    listed = ask("{ devices(unattached: true) { id label userAgent } }", held).dig("data", "devices")

    assert_equal [ "curl/8" ], listed.map { |one| one["userAgent"] }

    blocked = ask(%(mutation { blockDevice(id: "#{listed.sole['id']}") { device { blockedAt } } }), held)

    assert_not_nil blocked.dig("data", "blockDevice", "device", "blockedAt")
  end

  test "a nickname is writable, so a rename does not mean a new account" do
    body = ask(<<~GQL, bearer)
      mutation { updateActor(uuid: "#{@actor.uuid}", nickname: "renamed") { actor { nickname } } }
    GQL

    assert_equal "renamed", body.dig("data", "updateActor", "actor", "nickname")
    assert_equal "renamed", within(@tenant) { @actor.reload.nickname }
  end

  test "a nickname cannot be emptied on the way through" do
    body = ask(%(mutation { updateActor(uuid: "#{@actor.uuid}", nickname: "") { actor { uuid } } }), bearer)

    assert_match(/nickname/i, body["errors"].first["message"])
  end

  test "signing an actor out ends every session and refresh token they hold" do
    held = bearer
    second = create_actor(@tenant, nickname: "second")

    within(@tenant) do
      Session.start!(actor: second)
      RefreshToken.mint!(actor: second, client: @client)
    end

    ask(%(mutation { signOutActor(uuid: "#{second.uuid}") { actor { uuid } } }), held)

    within(@tenant) do
      assert_empty Session.live.where(actor: second).to_a
      assert_empty RefreshToken.live.where(actor: second).to_a
    end
  end

  test "deleting an actor takes everything that pointed at them with it" do
    held = bearer
    second = create_actor(@tenant, nickname: "second")
    approved = create_client(@tenant, name: "Theirs", approved_at: Time.current, approved_by: second)

    within(@tenant) do
      Session.start!(actor: second)
      Consent.create!(actor: second, client: @client, scopes: "openid")
      RefreshToken.mint!(actor: second, client: @client)
    end

    body = ask(%(mutation { deleteActor(uuid: "#{second.uuid}") { uuid nickname } }), held)

    assert_nil body["errors"]
    assert_equal "second", body.dig("data", "deleteActor", "nickname")

    within(@tenant) do
      assert_nil Actor.find_by(uuid: second.uuid)
      assert_empty Session.where(actor_id: second.id).to_a
      assert_empty Consent.where(actor_id: second.id).to_a
      assert_empty Token.where(actor_id: second.id).to_a
      assert_nil approved.reload.approved_by_id
    end
  end

  test "an admin cannot delete themselves" do
    body = ask(%(mutation { deleteActor(uuid: "#{@actor.uuid}") { uuid } }), bearer)

    assert_match "would lock you out", body["errors"].first["message"]
    assert_not_nil within(@tenant) { Actor.find_by(uuid: @actor.uuid) }
  end

  def admin
    @admin ||= bearer
  end

  def invite(nickname: "sam", email: "sam@example.com", password: nil, scopes: nil)
    ask(<<~GQL, admin)
      mutation {
        createActor(
          nickname: "#{nickname}"
          #{email ? ", email: \"#{email}\"" : ''}
          #{password ? ", password: \"#{password}\"" : ''}
          #{scopes ? ", scopes: #{scopes.inspect}" : ''}
        ) {
          delivered url actor { uuid nickname activated emailVerified invitedAt }
        }
      }
    GQL
  end

  test "an admin invites somebody, and gets a link back when there is no mailer" do
    body = invite

    invited = body.dig("data", "createActor")

    assert_nil body["errors"]
    assert_equal false, invited["delivered"]
    assert_match %r{/invite/}, invited["url"]
    assert_equal false, invited.dig("actor", "activated")
    assert_not_nil invited.dig("actor", "invitedAt")
  end

  test "with a mailer configured the link is mailed and never handed to the admin" do
    with_mailer do
      body = invite

      invited = body.dig("data", "createActor")

      assert_equal true, invited["delivered"]
      assert_nil invited["url"]
      assert_equal 1, enqueued_jobs.count { |job| job[:args].first == "ActorMailer" }
    end
  end

  test "an admin adds somebody with no address at all, and hands the link over" do
    body = invite(email: nil)

    invited = body.dig("data", "createActor")

    assert_nil body["errors"]
    assert_equal false, invited["delivered"]
    assert_match %r{/invite/}, invited["url"]
    assert_equal false, invited.dig("actor", "activated")
  end

  test "an admin sets the password, and that actor is activated without a link" do
    body = invite(email: nil, password: "correct-horse")

    created = body.dig("data", "createActor")

    assert_nil body["errors"]
    assert_equal true, created.dig("actor", "activated")
    assert_nil created["url"]

    within(@tenant) do
      assert_not_nil Actor.authenticate("sam", "correct-horse")
    end
  end

  test "an admin-set password still has to clear the minimum" do
    body = invite(password: "short")

    assert_match(/at least #{Actor::MINIMUM_PASSWORD}/, body["errors"].first["message"])
    assert_nil within(@tenant) { Actor.find_by(nickname: "sam") }
  end

  test "an admin-set password leaves the address unconfirmed, and opens a link for it" do
    created = invite(password: "correct-horse").dig("data", "createActor")

    assert_equal false, created.dig("actor", "emailVerified")
    assert_match %r{/verify/}, created["url"]
  end

  test "an invitation carries the scopes it names, the way setActorScopes does" do
    body = ask(<<~GQL, bearer)
      mutation {
        createActor(nickname: "sam", email: "sam@example.com", scopes: ["openid", "masks:manage"]) {
          actor { scopes }
        }
      }
    GQL

    assert_includes body.dig("data", "createActor", "actor", "scopes"), "masks:manage"
  end

  test "an invited nickname already in use is refused rather than duplicated" do
    invite

    assert_match(/nickname/i, invite["errors"].first["message"])
  end

  test "an invitation can be resent, and the admin cannot resend to somebody activated" do
    invited = invite.dig("data", "createActor", "actor", "uuid")

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

    waiting = invite.dig("data", "createActor", "actor", "uuid")

    refused = ask(<<~GQL, admin)
      mutation { resetPassword(uuid: "#{waiting}") { delivered } }
    GQL

    assert_match(/has not accepted/, refused["errors"].first["message"])
  end

  def png(width = 900, height = 300)
    Vips::Image.black(width, height)
      .add(120).cast(:uchar)
      .bandjoin([ Vips::Image.black(width, height).add(60).cast(:uchar),
                  Vips::Image.black(width, height).add(200).cast(:uchar) ])
      .copy(interpretation: :srgb)
      .pngsave_buffer
  end

  def photo(bytes = png)
    file = Tempfile.new([ "avatar", ".png" ], binmode: true)
    file.write(bytes)
    file.rewind

    Rack::Test::UploadedFile.new(file.path, "image/png")
  end

  UPLOAD = <<~GQL.freeze
    mutation Upload($uuid: ID!, $photo: Upload!) {
      uploadAvatar(uuid: $uuid, photo: $photo) { actor { uuid avatars { photo } } }
    }
  GQL

  def upload(uuid:, token: admin, file: photo)
    post manage_graphql_path,
         params: {
           operations: {
             query: UPLOAD, variables: { uuid: uuid, photo: nil }
           }.to_json,
           map: { "0" => [ "variables.photo" ] }.to_json,
           "0" => file
         },
         headers: { "Authorization" => "Bearer #{token}" }
  end

  test "an admin uploads a photo over the multipart spec, squared and re-encoded" do
    subject = within(@tenant) { create_actor(@tenant, nickname: "sam") }

    upload(uuid: subject.uuid)

    assert_response :success
    assert_nil response.parsed_body["errors"]
    assert_match %r{/avatars/#{subject.uuid}},
                 response.parsed_body.dig("data", "uploadAvatar", "actor", "avatars", "photo")

    within(@tenant) do
      held = Avatar.sole
      square = Vips::Image.new_from_buffer(held.data, "")

      assert_equal subject.id, held.actor_id
      assert_equal Avatar::CONTENT_TYPE, held.content_type
      assert_equal [ Avatar::STORED, Avatar::STORED ], [ square.width, square.height ]
    end
  end

  test "an upload that is not an image is refused rather than stored" do
    upload(uuid: @actor.uuid, file: Rack::Test::UploadedFile.new(__FILE__, "image/png"))

    assert_match(/has to be an image/, response.parsed_body["errors"].first["message"])
    assert_equal 0, within(@tenant) { Avatar.count }
  end

  test "uploading for an unknown actor is refused" do
    upload(uuid: SecureRandom.uuid)

    assert_match(/no actor with that uuid/, response.parsed_body["errors"].first["message"])
    assert_equal 0, within(@tenant) { Avatar.count }
  end

  test "a variable the map never filled in is refused as a missing file" do
    post manage_graphql_path,
         params: {
           operations: { query: UPLOAD, variables: { uuid: @actor.uuid, photo: nil } }.to_json,
           map: {}.to_json
         },
         headers: { "Authorization" => "Bearer #{admin}" }

    assert response.parsed_body["errors"].any?
    assert_equal 0, within(@tenant) { Avatar.count }
  end

  test "a token without masks:manage cannot upload a photo for anybody" do
    plain = create_actor(@tenant, nickname: "plain", scopes: "openid profile email")

    upload(uuid: @actor.uuid, token: bearer(scope: "openid", actor: plain))

    assert_response :forbidden
    assert_match(/insufficient_scope/, response.parsed_body["error"])
    assert_equal 0, within(@tenant) { Avatar.count }
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

  def stage(token)
    ask(%(mutation { stageSigningKey { signingKey { kid state } } }), token)
      .dig("data", "stageSigningKey", "signingKey")
  end

  test "a staged key is published before it signs anything" do
    signing = within(@tenant) { SigningKey.active.first.kid }
    staged = stage(bearer)

    assert_equal "staged", staged["state"]
    assert_not_equal signing, staged["kid"]
    assert_equal signing, within(@tenant) { SigningKey.active.first.kid }

    get "/.well-known/jwks.json"

    assert_includes JSON.parse(response.body)["keys"].map { |key| key["kid"] }, staged["kid"]
  end

  test "only one key may be staged at a time" do
    held = bearer
    stage(held)

    body = ask(%(mutation { stageSigningKey { signingKey { kid } } }), held)

    assert_match "already staged", body["errors"].first["message"]
    assert_equal 1, within(@tenant) { SigningKey.staged.count }
  end

  test "activating a staged key retires the outgoing one after an overlap" do
    held = bearer
    outgoing = within(@tenant) { SigningKey.active.first }
    staged = stage(held)

    body = ask(
      %(mutation { activateSigningKey(kid: "#{staged['kid']}") { signingKey { state } } }), held
    )

    assert_equal "active", body.dig("data", "activateSigningKey", "signingKey", "state")
    assert_equal staged["kid"], within(@tenant) { SigningKey.active.first.kid }

    retired = within(@tenant) { outgoing.reload.retired_at }

    assert_operator retired, :>, Time.current
    assert_in_delta SigningKey::OVERLAP.from_now.to_f, retired.to_f, 5

    assert_nil ask("{ viewer { nickname } }", held)["errors"]
  end

  test "a key already signing cannot be activated again" do
    held = bearer
    signing = within(@tenant) { SigningKey.active.first.kid }

    body = ask(%(mutation { activateSigningKey(kid: "#{signing}") { signingKey { state } } }), held)

    assert_match "already signing", body["errors"].first["message"]
  end

  test "a staged key can be discarded, and a signing key cannot" do
    held = bearer
    staged = stage(held)

    refused = ask(
      %(mutation { discardSigningKey(kid: "#{within(@tenant) { SigningKey.active.first.kid }}") { kid } }),
      held
    )

    assert_match "only a staged key", refused["errors"].first["message"]

    body = ask(%(mutation { discardSigningKey(kid: "#{staged['kid']}") { kid } }), held)

    assert_equal staged["kid"], body.dig("data", "discardSigningKey", "kid")
    assert_empty within(@tenant) { SigningKey.staged.to_a }
  end

  test "rotating stages and activates in one step" do
    held = bearer
    outgoing = within(@tenant) { SigningKey.active.first }

    body = ask(%(mutation { rotateSigningKey { signingKey { kid state } } }), held)
    minted = body.dig("data", "rotateSigningKey", "signingKey")

    assert_equal "active", minted["state"]
    assert_not_equal outgoing.kid, minted["kid"]
    assert_equal minted["kid"], within(@tenant) { SigningKey.active.first.kid }
    assert_empty within(@tenant) { SigningKey.staged.to_a }

    get "/.well-known/jwks.json"
    published = JSON.parse(response.body)["keys"].map { |key| key["kid"] }

    assert_includes published, minted["kid"]
    assert_includes published, outgoing.kid
  end

  test "signing keys carry the state the console badges them with" do
    held = bearer
    stage(held)
    within(@tenant) { SigningKey.rotate!(tenant: @tenant) }

    states = ask("{ tenant { signingKeys { state } } }", held)
      .dig("data", "tenant", "signingKeys").map { |key| key["state"] }

    assert_equal %w[active retiring staged].sort, states.sort
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

  test "claimed namespaces are listed with the resource that holds them" do
    token = bearer
    claim!

    held = ask("{ namespaces { name resource client { name } } }", token)["data"]["namespaces"]

    assert_equal [ "things:" ], held.map { |one| one["name"] }
    assert_equal "https://demo.things.test/mcp", held.first["resource"]
    assert_equal "things", held.first.dig("client", "name")
  end

  test "a namespace its client still holds cannot be released" do
    token = bearer
    claim!

    body = ask('mutation { releaseNamespace(name: "things:") { released } }', token)

    assert_match "is in use by things", body.dig("errors", 0, "message")
    assert within(@tenant) { Namespace.exists?(name: "things:") }
  end

  test "releasing an archived namespace frees the name" do
    token = bearer
    claim!

    within(@tenant) { Namespace.find_by(name: "things:").client.update!(archived_at: Time.current) }

    body = ask('mutation { releaseNamespace(name: "things:") { released } }', token)

    assert_equal "things:", body.dig("data", "releaseNamespace", "released")
    assert_not within(@tenant) { Namespace.exists?(name: "things:") }
  end

  private

    def claim!(resource: "https://demo.things.test/mcp", name: "things:")
      within(@tenant) do
        holder = create_client(@tenant, name: "things", allowed_scopes: "openid #{name}",
                               approved_at: Time.current)

        Namespace.create!(name: name, resource: resource, client: holder, claimed_at: Time.current)
      end
    end
end
