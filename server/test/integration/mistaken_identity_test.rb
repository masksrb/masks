require "test_helper"
require_relative "../support/fake_authenticator"
require_relative "../support/upstream"

class MistakenIdentityTest < ActionDispatch::IntegrationTest
  include Federated

  API = "https://api.probe.example.com".freeze
  OTHER_API = "https://other.probe.example.com".freeze

  setup do
    host! host_for(@tenant)

    @alice = create_actor(nickname: "alice", email: "alice@probe.example.com")
    @mallory = create_actor(nickname: "mallory", email: "mallory@probe.example.com")
    @registration = register
  end

  def step(event, rid: nil, **updates)
    post "/login", params: { event: event, rid: rid, **updates }.compact, as: :json

    JSON.parse(response.body)
  end

  def redeem(code, registration = @registration, **params)
    token(
      grant_type: "authorization_code", code: code,
      redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier,
      client_id: registration["client_id"], client_secret: registration["client_secret"],
      **params
    )
  end

  def sub_in(jwt)
    claims_in(jwt)["sub"]
  end

  def uuid_of(actor)
    within { actor.reload.uuid }
  end

  def finish(settled)
    get settled["redirectTo"]
    consent! if awaiting_consent?

    redeem(code_from)
  end

  # a sign-in names whoever proved themselves, and nobody else

  test "re-authenticating as somebody else names the person who just proved themselves" do
    sign_in_as(@alice)
    authorize(client_id: @registration["client_id"], prompt: "login")

    rid = current_rid

    step("start-over", rid: rid)
    step("identify", rid: rid, identifier: "mallory")
    settled = step("password", rid: rid, password: "password")

    assert_equal uuid_of(@mallory), sub_in(finish(settled)["id_token"])
  end

  test "re-authenticating as somebody else ends the session it replaced" do
    sign_in_as(@alice)
    authorize(client_id: @registration["client_id"], prompt: "login")

    rid = current_rid

    step("start-over", rid: rid)
    step("identify", rid: rid, identifier: "mallory")
    finish(step("password", rid: rid, password: "password"))

    assert_equal [ @mallory.id ], within { Session.live.pluck(:actor_id) }
  end

  test "a second factor proved by one account does not satisfy another's" do
    enable_otp(@alice)
    mallory = enable_otp(@mallory)

    authorize(client_id: @registration["client_id"])
    rid = current_rid

    step("identify", rid: rid, identifier: "mallory")
    step("password", rid: rid, password: "password")
    assert_equal "consent", step("otp", rid: rid, code: mallory.now)["prompt"]

    step("identify", rid: rid, identifier: "alice")

    assert_equal "second-factor", step("password", rid: rid, password: "password")["prompt"]
  end

  test "a one time password is spent by the sign-in that used it" do
    code = enable_otp(@alice).now

    assert_equal "settled", step("identify", identifier: "alice") &&
                            step("password", password: "password") &&
                            step("otp", code: code)["prompt"]

    reset!
    host! host_for(@tenant)

    step("identify", identifier: "alice")
    step("password", password: "password")

    assert_equal "second-factor", step("otp", code: code)["prompt"]
  end

  test "the methods a login reports are those of the person it settled on" do
    mallory = enable_otp(@mallory)

    authorize(client_id: @registration["client_id"])
    rid = current_rid

    step("identify", rid: rid, identifier: "mallory")
    step("password", rid: rid, password: "password")
    step("otp", rid: rid, code: mallory.now)

    step("identify", rid: rid, identifier: "alice")
    settled = step("password", rid: rid, password: "password")

    claims = claims_in(finish(settled)["id_token"])

    assert_equal uuid_of(@alice), claims["sub"]
    assert_equal [ "pwd" ], claims["amr"]
  end

  test "a passkey belonging to somebody else signs that person in, not the one already here" do
    authenticator = FakeAuthenticator.new(origin_for(@tenant))

    sign_in_as(@mallory)
    post "/account/passkeys/challenge"
    post "/account/passkeys",
         params: { credential: JSON.generate(authenticator.enrol(JSON.parse(response.body))) }

    reset!
    host! host_for(@tenant)

    sign_in_as(@alice)
    authorize(client_id: @registration["client_id"], prompt: "login")
    rid = current_rid

    offer = step("passkey:challenge", rid: rid)
    credential = authenticator.assert(offer.dig("passkey", "options"))
    settled = step("passkey:verify", rid: rid, passkey: JSON.generate(credential))

    assert_equal uuid_of(@mallory), sub_in(finish(settled)["id_token"])
    assert_empty within { Session.live.where(actor_id: @alice.id).to_a }
  end

  test "approving a device names the person who proved themselves" do
    device = register(@tenant, grant_types: [ "authorization_code", DeviceGrant::GRANT_TYPE ])

    post "/device_authorization",
         params: { client_id: device["client_id"], client_secret: device["client_secret"], scope: "openid" }

    asked = JSON.parse(response.body)

    sign_in_as(@alice)

    get "/device?#{URI.encode_www_form(user_code: asked['user_code'])}"
    rid = current_rid

    step("start-over", rid: rid)
    step("identify", rid: rid, identifier: "mallory")
    step("password", rid: rid, password: "password")

    get "/device?#{URI.encode_www_form(user_code: asked['user_code'])}"
    consent! if awaiting_consent?

    granted = token(
      grant_type: DeviceGrant::GRANT_TYPE, device_code: asked["device_code"],
      client_id: device["client_id"], client_secret: device["client_secret"]
    )

    assert_equal uuid_of(@mallory), sub_in(granted["id_token"])
  end

  # a token reaches only what the person granted

  test "the token endpoint cannot name a resource the authorization did not carry" do
    sign_in_as(@alice)
    authorize(client_id: @registration["client_id"])
    consent! if awaiting_consent?

    body = redeem(code_from, resource: API)

    assert_equal "invalid_target", body["error"]
  end

  test "the token endpoint cannot widen the resources the authorization carried" do
    sign_in_as(@alice)
    authorize(client_id: @registration["client_id"], resource: API)
    consent! if awaiting_consent?

    body = redeem(code_from, resource: [ API, OTHER_API ])

    assert_equal "invalid_target", body["error"]
  end

  test "a refresh cannot widen the resources the grant carried" do
    sign_in_as(@alice)
    authorize(client_id: @registration["client_id"], scope: "openid offline_access", resource: API)
    consent! if awaiting_consent?

    issued = redeem(code_from)

    body = token(
      grant_type: "refresh_token", refresh_token: issued["refresh_token"],
      client_id: @registration["client_id"], client_secret: @registration["client_secret"],
      resource: OTHER_API
    )

    assert_equal "invalid_target", body["error"]
  end

  test "a refresh cannot widen the scope the grant carried" do
    sign_in_as(@alice)
    authorize(client_id: @registration["client_id"], scope: "openid offline_access")
    consent! if awaiting_consent?

    issued = redeem(code_from)

    body = token(
      grant_type: "refresh_token", refresh_token: issued["refresh_token"],
      client_id: @registration["client_id"], client_secret: @registration["client_secret"],
      scope: "openid profile email"
    )

    refute_includes Scopes.list(body["scope"]), "email"
    refute_includes Scopes.list(body["scope"]), "profile"
  end

  test "an exchange cannot widen an audience the grant never named" do
    exchanging = register(
      @tenant, grant_types: [ "authorization_code", Exchange::GRANT_TYPE ]
    )

    sign_in_as(@alice)
    authorize(client_id: exchanging["client_id"])
    consent! if awaiting_consent?

    issued = redeem(code_from, exchanging)

    body = token(
      grant_type: Exchange::GRANT_TYPE,
      subject_token: issued["access_token"],
      subject_token_type: Exchange::ACCESS_TOKEN,
      client_id: exchanging["client_id"], client_secret: exchanging["client_secret"],
      resource: API
    )

    assert_equal "invalid_target", body["error"]
  end

  test "an exchange keeps naming the person the subject token named" do
    exchanging = register(
      @tenant, grant_types: [ "authorization_code", Exchange::GRANT_TYPE ]
    )

    sign_in_as(@alice)
    authorize(client_id: exchanging["client_id"])
    consent! if awaiting_consent?

    issued = redeem(code_from, exchanging)

    body = token(
      grant_type: Exchange::GRANT_TYPE,
      subject_token: issued["access_token"],
      subject_token_type: Exchange::ACCESS_TOKEN,
      client_id: exchanging["client_id"], client_secret: exchanging["client_secret"]
    )

    claims = claims_in(body["access_token"])

    assert_equal uuid_of(@alice), claims["sub"]
    assert_equal exchanging["client_id"], claims.dig("act", "sub")
  end

  test "a scope the client allows but the person does not hold never reaches a token" do
    within { @alice.update!(scopes: "openid") }

    client = create_client(@tenant, allowed_scopes: "openid profile email masks:manage")

    sign_in_as(@alice)
    authorize(client_id: client.client_id, scope: "openid profile masks:manage")
    consent! if awaiting_consent?

    body = token(
      grant_type: "authorization_code", code: code_from,
      redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier,
      client_id: client.client_id
    )

    assert_equal [ "openid" ], Scopes.list(claims_in(body["access_token"])["scope"])
  end

  test "the manage api refuses a token that was not issued for it" do
    within { @alice.update!(scopes: "openid masks:manage") }

    client = create_client(@tenant, allowed_scopes: "openid masks:manage", approved_at: Time.current)

    sign_in_as(@alice)
    authorize(client_id: client.client_id, scope: "openid masks:manage")
    consent! if awaiting_consent?

    body = token(
      grant_type: "authorization_code", code: code_from,
      redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier,
      client_id: client.client_id
    )

    post "/manage/graphql",
         params: { query: "{ actors { edges { node { nickname } } } }" }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer #{body['access_token']}"
         }

    assert_response :unauthorized
  end

  test "the manage api refuses a token whose person no longer holds the scope" do
    within { @alice.update!(scopes: "openid masks:manage") }

    client = create_client(@tenant, allowed_scopes: "openid masks:manage", approved_at: Time.current)
    resource = issuer_for(@tenant).manage_resource

    sign_in_as(@alice)
    authorize(client_id: client.client_id, scope: "openid masks:manage", resource: resource)
    consent! if awaiting_consent?

    body = token(
      grant_type: "authorization_code", code: code_from,
      redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier,
      client_id: client.client_id
    )

    within { @alice.update!(scopes: "openid") }

    post "/manage/graphql",
         params: { query: "{ actors { edges { node { nickname } } } }" }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer #{body['access_token']}"
         }

    assert_response :unauthorized
  end

  # one client's grant is not another's

  test "a refresh token issued to one client is not redeemable by another" do
    stranger = register(@tenant, client_name: "stranger")

    sign_in_as(@alice)
    authorize(client_id: @registration["client_id"], scope: "openid offline_access")
    consent! if awaiting_consent?

    issued = redeem(code_from)

    body = token(
      grant_type: "refresh_token", refresh_token: issued["refresh_token"],
      client_id: stranger["client_id"], client_secret: stranger["client_secret"]
    )

    assert_equal "invalid_grant", body["error"]
  end

  test "a device code issued to one client is not redeemable by another" do
    grants = [ "authorization_code", DeviceGrant::GRANT_TYPE ]
    device = register(@tenant, grant_types: grants)
    stranger = register(@tenant, client_name: "stranger", grant_types: grants)

    post "/device_authorization",
         params: { client_id: device["client_id"], client_secret: device["client_secret"], scope: "openid" }

    asked = JSON.parse(response.body)

    sign_in_as(@alice)
    get "/device?#{URI.encode_www_form(user_code: asked['user_code'])}"
    consent! if awaiting_consent?

    body = token(
      grant_type: DeviceGrant::GRANT_TYPE, device_code: asked["device_code"],
      client_id: stranger["client_id"], client_secret: stranger["client_secret"]
    )

    assert_equal "invalid_grant", body["error"]
  end

  test "a client cannot revoke a token another client holds" do
    stranger = register(@tenant, client_name: "stranger")

    sign_in_as(@alice)
    authorize(client_id: @registration["client_id"], scope: "openid offline_access")
    consent! if awaiting_consent?

    issued = redeem(code_from)

    post "/revoke",
         params: {
           token: issued["refresh_token"],
           client_id: stranger["client_id"], client_secret: stranger["client_secret"]
         }

    assert_response :ok

    rotated = token(
      grant_type: "refresh_token", refresh_token: issued["refresh_token"],
      client_id: @registration["client_id"], client_secret: @registration["client_secret"]
    )

    assert rotated["access_token"].present?
  end

  test "a client that declares somebody else's resource cannot read their tokens" do
    sign_in_as(@alice)
    authorize(client_id: @registration["client_id"], resource: API)
    consent! if awaiting_consent?

    issued = redeem(code_from)
    stranger = register(@tenant, client_name: "stranger", resources: [ API ])

    post "/introspect",
         params: {
           token: issued["access_token"],
           client_id: stranger["client_id"], client_secret: stranger["client_secret"]
         }

    assert_equal false, JSON.parse(response.body)["active"]
  end

  # one person's account is not another's

  test "userinfo answers for the token that asked, and for nobody else" do
    mine = access_token_for(actor: @alice, registration: @registration)

    reset!
    host! host_for(@tenant)

    theirs = access_token_for(actor: @mallory, registration: @registration)

    get "/userinfo", headers: { "HTTP_AUTHORIZATION" => "Bearer #{mine['access_token']}" }
    assert_equal uuid_of(@alice), JSON.parse(response.body)["sub"]

    get "/userinfo", headers: { "HTTP_AUTHORIZATION" => "Bearer #{theirs['access_token']}" }
    assert_equal uuid_of(@mallory), JSON.parse(response.body)["sub"]
  end

  test "a logout hint naming somebody else does not end the session that is here" do
    held = access_token_for(actor: @mallory, registration: @registration)

    reset!
    host! host_for(@tenant)

    sign_in_as(@alice)
    get "/logout?id_token_hint=#{CGI.escape(held['id_token'])}"

    assert_response :success
    assert_equal 1, within { Session.live.where(actor_id: @alice.id).count }
  end

  test "a logout hint naming the person who is here ends their session without asking" do
    sign_in_as(@alice)
    authorize(client_id: @registration["client_id"])
    consent! if awaiting_consent?

    held = redeem(code_from)

    get "/logout?id_token_hint=#{CGI.escape(held['id_token'])}"

    assert_response :redirect
    assert_empty within { Session.live.to_a }
  end

  # a federated identity reaches an account only by proving it

  test "an upstream identity does not reach an account by naming its address" do
    create_provider
    within { @alice.update!(email_verified_at: Time.current) }

    finish_sso(sub: "intruder", email: "alice@probe.example.com")

    assert_nil signed_in_actor
    assert_nil within { Connection.find_by(subject: "intruder") }
  end

  test "an upstream identity reaches the account once that account proves itself" do
    create_provider
    within { @alice.update!(email_verified_at: Time.current) }

    finish_sso(sub: "upstream-alice", email: "alice@probe.example.com")
    prove

    assert_equal @alice.id, signed_in_actor&.id
    assert_equal @alice.id, within { Connection.live.find_by(subject: "upstream-alice").actor_id }
  end

  test "the proof that links an upstream identity has to be the matched account's" do
    create_provider
    within { @alice.update!(email_verified_at: Time.current) }

    finish_sso(sub: "intruder", email: "alice@probe.example.com")

    post "/login", params: { event: "identify", identifier: "mallory" }, as: :json
    prove

    assert_equal @mallory.id, signed_in_actor&.id
    assert_nil within { Connection.find_by(subject: "intruder") }
  end

  test "a provider answering for no domain provisions nobody" do
    create_provider(provisions: true)

    finish_sso(sub: "stranger", email: "stranger@probe.example.com")

    assert_nil signed_in_actor
    assert_equal 2, within { Actor.count }
  end

  test "a provider is bound to a claim its issuer never reassigns" do
    within do
      provider = Provider.new(key: "loose", name: "Loose", subject_claim: "email")

      assert_not provider.valid?
      assert_match(/never reassigns/, provider.errors.full_messages.join)
    end
  end

  # one tenant's identity is not another's

  test "an access token minted in one tenant is refused in another" do
    held = access_token_for(actor: @alice, registration: @registration)

    create_actor(other_tenant, nickname: "alice", email: "alice@probe.example.com")
    host! host_for(other_tenant)

    get "/userinfo", headers: { "HTTP_AUTHORIZATION" => "Bearer #{held['access_token']}" }

    assert_response :unauthorized
  end

  test "a session cookie from one tenant signs nobody in at another" do
    sign_in_as(@alice)

    create_actor(other_tenant, nickname: "alice", email: "alice@probe.example.com")
    elsewhere = register(other_tenant)

    host! host_for(other_tenant)
    authorize(client_id: elsewhere["client_id"])

    assert awaiting_login?
  end

  test "a client registered in one tenant is unknown in another" do
    host! host_for(other_tenant)
    create_actor(other_tenant, nickname: "alice", email: "alice@probe.example.com")

    authorize(client_id: @registration["client_id"])

    assert_response :bad_request
    refute response.redirect?
  end

  # ending an account's access ends it everywhere

  test "changing a password ends the other sessions and the refresh tokens" do
    issued = access_token_for(
      actor: @alice, registration: @registration
    )

    assert issued["refresh_token"].present?

    patch "/account/password",
          params: { current_password: "password", password: "another-password" }

    body = token(
      grant_type: "refresh_token", refresh_token: issued["refresh_token"],
      client_id: @registration["client_id"], client_secret: @registration["client_secret"]
    )

    assert_equal "invalid_grant", body["error"]
  end
end
