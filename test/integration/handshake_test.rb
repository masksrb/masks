require "test_helper"

class HandshakeTest < ActionDispatch::IntegrationTest
  APP = "https://demo.uris.test".freeze
  RESOURCE = "#{APP}/mcp".freeze
  RETURN_TO = "#{APP}/auth/handshake/callback".freeze
  REDIRECT_URI = "#{APP}/auth/masks/callback".freeze
  SCOPE = "openid profile email offline_access uris:catalog:read".freeze

  setup do
    @owner = create_actor(@tenant, nickname: "owner", password: "password",
                          scopes: Scopes.join(Scopes::STANDARD + [ Scopes::HANDSHAKE, "uris:catalog:read" ]))
    host! host_for(@tenant)
  end

  def connect(redirect_uris: [ REDIRECT_URI ], **overrides)
    params = {
      client_name: "uris",
      resource: RESOURCE,
      scope: SCOPE,
      return_to: RETURN_TO,
      state: "app-state"
    }.merge(overrides).compact

    query = params.to_a
    Array(redirect_uris).each { |uri| query << [ "redirect_uris", uri ] }

    get "/handshake?#{URI.encode_www_form(query)}"
  end

  def current_hid
    hidden_value("hid")
  end

  def current_shown
    hidden_value("shown")
  end

  def approve!
    approve_handshake
    redirected["initial_access_token"]
  end

  def decline!(hid: current_hid)
    post "/handshake", params: { deny: "yes", hid: hid }
  end

  def redeem(secret, **metadata)
    post "/register",
         params: { client_name: "something else", redirect_uris: [ "https://elsewhere.test/cb" ] }
           .merge(metadata).to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer #{secret}"
         }

    JSON.parse(response.body)
  end

  def approved
    within(@tenant) { Client.approved.sole }
  end

  BACKCHANNEL = "#{APP}/auth/logout/backchannel".freeze

  test "an app that asks to be told about logout is registered for it" do
    sign_in_as(@owner)
    connect(backchannel_logout_uri: BACKCHANNEL)
    approve!

    assert_equal BACKCHANNEL, approved.backchannel_logout_uri
  end

  test "a logout uri somewhere other than the app's own origin is refused" do
    sign_in_as(@owner)
    connect(backchannel_logout_uri: "https://elsewhere.test/out")

    assert_response :bad_request
    assert_match "must share the origin", response.body
  end

  test "an app that asks for nothing is registered for nothing" do
    sign_in_as(@owner)
    connect
    approve!

    assert_nil approved.backchannel_logout_uri
  end

  test "a signed-in owner is shown what is being connected, and where it will be sent back" do
    sign_in_as(@owner)
    connect

    assert_response :success
    assert_match "Register uris as a client?", response.body
    assert_match APP, response.body
    assert_match "uris:catalog:read", response.body
    assert_match REDIRECT_URI, response.body
  end

  test "approving mints a one-time token, and carries the app's state back with it" do
    sign_in_as(@owner)
    connect
    secret = approve!

    assert_equal RETURN_TO, redirected_uri.to_s.split("?").first
    assert_equal "app-state", redirected["state"]
    assert_equal issuer_for(@tenant).url, redirected["iss"]
    assert secret.present?
  end

  test "the token registers the approved client, server to server, exactly once" do
    sign_in_as(@owner)
    connect
    secret = approve!

    registration = redeem(secret)

    assert_response :created
    assert_equal approved.client_id, registration["client_id"]
    assert registration["client_secret"].present?
    assert registration["registration_access_token"].present?

    redeem(secret)

    assert_response :unauthorized
  end

  test "the registration body cannot widen what was approved" do
    sign_in_as(@owner)
    connect
    registration = redeem(approve!)

    assert_equal [ REDIRECT_URI ], registration["redirect_uris"]
    assert_equal "uris", registration["client_name"]
    assert_equal Scopes.list(SCOPE), Scopes.list(registration["scope"])
    assert_equal [ RESOURCE ], approved.resources
  end

  test "where a handshake returns to is where a logout may send that client back" do
    sign_in_as(@owner)
    connect
    redeem(approve!)

    assert_equal [ RETURN_TO ], approved.post_logout_redirect_uris

    delete "/logout", params: { client_id: approved.client_id, post_logout_redirect_uri: RETURN_TO }

    assert_redirected_to RETURN_TO
  end

  test "an app that will ask people for their accounts elsewhere is approved for delegation, and claims no namespace" do
    sign_in_as(@owner)
    connect(scope: "#{SCOPE} masks:delegate:")

    assert_includes response.body, "Ask each person to let it use their accounts elsewhere"

    approve!

    assert_includes approved.scope_list, "masks:delegate:"
    assert approved.grants?(Exchange::GRANT_TYPE)
    assert_equal 0, within(@tenant) { Namespace.count }
    assert_not within(@tenant) { @owner.reload.holds?("masks:delegate:") }
  end

  test "an approved client is not a dynamic one, and records who approved it" do
    sign_in_as(@owner)
    connect
    approve!

    assert_not approved.dynamic
    assert approved.approved?
    assert_equal @owner.id, approved.approved_by_id
  end

  test "an actor holding neither pairing scope is refused before anything is shown" do
    nobody = create_actor(@tenant, nickname: "nobody", password: "password")

    sign_in_as(nobody)
    connect

    assert_response :bad_request
    assert_equal 0, within(@tenant) { Client.count }
  end

  test "an approver cannot connect a client to more than they hold themselves" do
    sign_in_as(@owner)
    connect(scope: "openid masks:manage")

    assert_response :bad_request
    assert_equal 0, within(@tenant) { Client.count }
  end

  test "the scope an approver does not hold is named, so the refusal is actionable" do
    sign_in_as(@owner)
    connect(scope: "openid catalog:write")

    assert_match "catalog:write", response.body
  end

  test "masks:handshake cannot reconnect an application somebody else connected" do
    admin = create_actor(@tenant, nickname: "admin", password: "password",
                         scopes: Scopes.join(Scopes::STANDARD + [ Scopes::MANAGE ]))

    sign_in_as(admin)
    connect
    approve!

    held = approved.token_endpoint_auth_method

    reset!
    host! host_for(@tenant)
    sign_in_as(@owner)
    connect(token_endpoint_auth_method: "none", redirect_uris: [ "#{APP}/elsewhere" ])

    assert_response :bad_request
    assert_equal held, within(@tenant) { approved.token_endpoint_auth_method }
    assert_equal [ REDIRECT_URI ], within(@tenant) { approved.redirect_uris }
  end

  test "masks:handshake may reconnect the application it connected itself" do
    sign_in_as(@owner)
    connect
    approve!

    reset!
    host! host_for(@tenant)
    sign_in_as(@owner)
    connect

    assert_response :success
  end

  test "a manager holding masks:manage may pair the console with it" do
    admin = create_actor(@tenant, nickname: "admin", password: "password",
                         scopes: Scopes.join(Scopes::STANDARD + [ Scopes::MANAGE ]))

    sign_in_as(admin)
    connect(scope: "openid masks:manage")

    assert_response :success

    approve!

    assert_includes within(@tenant) { Client.approved.sole.scope_list }, Scopes::MANAGE
  end

  test "a manager approves a scope they do not hold, because they may grant it to themselves" do
    admin = create_actor(@tenant, nickname: "admin", password: "password",
                         scopes: Scopes.join(Scopes::STANDARD + [ Scopes::MANAGE ]))

    sign_in_as(admin)
    connect(scope: "openid catalog:write")

    assert_response :success

    approve!

    assert_includes within(@tenant) { Client.approved.sole.scope_list }, "catalog:write"
  end

  test "approving widens nobody — the approver already held what the app asked for" do
    held = within(@tenant) { @owner.scope_list }

    sign_in_as(@owner)
    connect
    approve!

    assert_equal held, within(@tenant) { @owner.reload.scope_list }
  end

  test "declining connects nothing and says so to the app" do
    sign_in_as(@owner)
    connect

    decline!

    assert_equal "access_denied", redirected["error"]
    assert_equal "app-state", redirected["state"]
    assert_equal 0, within(@tenant) { Client.count }
  end

  test "a redirect_uri at another origin is refused before anything is shown" do
    sign_in_as(@owner)
    connect(redirect_uris: [ REDIRECT_URI, "https://elsewhere.test/cb" ])

    assert_response :bad_request
    assert_match "must share the origin", response.body
  end

  test "a return_to at another origin is refused" do
    sign_in_as(@owner)
    connect(return_to: "https://elsewhere.test/callback")

    assert_response :bad_request
  end

  test "arriving with nothing to approve is refused rather than blank" do
    sign_in_as(@owner)

    get "/handshake"

    assert_response :bad_request
    assert_match "no connection request is in progress", response.body
  end

  test "approving the screen that was rendered connects that app, not the newer one" do
    other = "https://other.uris.test"

    sign_in_as(@owner)

    connect
    theirs = current_hid
    shown = response.body

    connect(
      client_name: "other", resource: "#{other}/mcp",
      return_to: "#{other}/auth/handshake/callback",
      redirect_uris: [ "#{other}/auth/masks/callback" ]
    )
    refute_equal theirs, current_hid

    approve_handshake(body: shown)

    assert response.location.start_with?(RETURN_TO), "connected the wrong app"

    assert_equal [ "uris" ], within(@tenant) { Client.all.map(&:name) }
  end

  test "a hid from another browser connects nothing" do
    sign_in_as(@owner)
    connect

    stolen = current_hid

    reset!
    host! host_for(@tenant)
    sign_in_as(@owner)

    post "/handshake", params: { approve: "yes", hid: stolen }

    assert_response :bad_request
    assert_equal 0, within(@tenant) { Client.count }
  end

  test "a connection request cannot be approved twice" do
    sign_in_as(@owner)
    connect

    hid = current_hid

    assert approve!.present?

    post "/handshake", params: { approve: "yes", hid: hid }

    assert_response :bad_request
    assert_equal 1, within(@tenant) { Client.count }
  end

  test "a second run for the same resource rotates the client rather than adding one" do
    sign_in_as(@owner)
    connect
    first = redeem(approve!)

    connect
    second = redeem(approve!)

    assert_equal 1, within(@tenant) { Client.count }
    assert_equal first["client_id"], second["client_id"]
    assert_not_equal first["client_secret"], second["client_secret"]
  end

  test "approving before the countdown ends registers nothing and goes back to the request" do
    sign_in_as(@owner)
    connect

    post "/handshake", params: { approve: "yes", hid: current_hid, shown: current_shown }

    assert_response :redirect
    assert_match %r{/handshake\?hid=}, response.location
    assert_equal 0, within(@tenant) { Client.count }

    follow_redirect!

    assert_response :success
    assert_match "Nothing was registered", response.body
  end

  test "a forged countdown stamp does not skip the wait" do
    sign_in_as(@owner)
    connect

    travel(HandshakesController::WAIT + 1.second) { post "/handshake", params: { approve: "yes", hid: current_hid, shown: "forged" } }

    assert_equal 0, within(@tenant) { Client.count }
  end

  test "a countdown stamp from another request does not skip the wait" do
    sign_in_as(@owner)
    connect
    theirs = current_hid

    connect(client_name: "other", resource: "https://other.uris.test/mcp",
            return_to: "https://other.uris.test/auth/handshake/callback",
            redirect_uris: [ "https://other.uris.test/auth/masks/callback" ])

    travel(HandshakesController::WAIT + 1.second) { post "/handshake", params: { approve: "yes", hid: theirs, shown: current_shown } }

    assert_equal 0, within(@tenant) { Client.count }
  end

  test "the request says it registers a client for everyone and allows only your account" do
    sign_in_as(@owner)
    connect

    assert_match "Registers on", response.body
    assert_match "Every sign-in through", response.body
    assert_match "Allows your account", response.body
    assert_match "Confidential. It receives a secret.", response.body
    assert_match RETURN_TO, response.body
  end

  test "a public client is said to hold no secret" do
    sign_in_as(@owner)
    connect(token_endpoint_auth_method: "none")

    assert_match "Public. It holds no secret.", response.body
  end

  test "asking for masks:manage is called out" do
    manager = create_actor(@tenant, nickname: "manager", password: "password",
                                    scopes: Scopes.join(Scopes::STANDARD + [ Scopes::MANAGE ]))
    sign_in_as(manager)
    connect(scope: "#{SCOPE} masks:manage")

    assert_match "change every setting on this server", response.body
  end

  test "replacing a client says whose it was and when it was approved" do
    sign_in_as(@owner)
    connect
    approve!

    connect

    assert_match "Replace the uris client?", response.body
    assert_match "The uris client you approved on", response.body
  end

  test "a token minted for one tenant registers nothing at another" do
    sign_in_as(@owner)
    connect
    secret = approve!

    reset!
    host! host_for(other_tenant)
    redeem(secret)

    assert_response :unauthorized
    assert_equal 0, within(other_tenant) { Client.count }
  end

  test "the setup prompt runs first when nobody has an account yet, and comes back here" do
    within(@tenant) { @owner.destroy! }

    connect

    assert_redirected_to login_path

    resumed = set_up!["redirectTo"]

    assert resumed.start_with?("/handshake?"), "setup did not come back to the connection request"

    get resumed

    assert_response :success
    assert_match "Register uris as a client?", response.body
  end

  test "an approved client does not ask again for what a person already approved" do
    sign_in_as(@owner)
    connect
    registration = redeem(approve!)

    authorize(client_id: registration["client_id"], redirect_uri: REDIRECT_URI, scope: SCOPE)

    assert_not awaiting_consent?
    assert code_from.present?
  end

  test "approving is the approver's consent, and it is recorded like any other" do
    sign_in_as(@owner)
    connect
    registration = redeem(approve!)

    within(@tenant) do
      client = Client.find_by!(client_id: registration["client_id"])
      consent = Consent.live.find_by!(actor: @owner, client: client)

      assert_equal Scopes.list(SCOPE), Scopes.list(consent.scopes)
      assert_equal [ RESOURCE ], consent.audience
      assert Event.exists?(action: Event::CONSENT_GRANTED, actor: @owner, client: client)
    end
  end

  test "somebody other than the approver is asked before an approved client gets anything" do
    sign_in_as(@owner)
    connect
    registration = redeem(approve!)

    colleague = create_actor(@tenant, nickname: "colleague", password: "password",
                             scopes: Scopes.join(Scopes::STANDARD + [ "uris:catalog:read" ]))
    reset!
    host! host_for(@tenant)
    sign_in_as(colleague)

    authorize(client_id: registration["client_id"], redirect_uri: REDIRECT_URI, scope: SCOPE)

    assert awaiting_consent?
  end

  test "an approved client whose consent is switched off asks nobody" do
    sign_in_as(@owner)
    connect
    registration = redeem(approve!)
    within(@tenant) { Client.find_by!(client_id: registration["client_id"]).update!(consent_required: false) }

    colleague = create_actor(@tenant, nickname: "colleague", password: "password",
                             scopes: Scopes.join(Scopes::STANDARD + [ "uris:catalog:read" ]))
    reset!
    host! host_for(@tenant)
    sign_in_as(colleague)

    authorize(client_id: registration["client_id"], redirect_uri: REDIRECT_URI, scope: SCOPE)

    assert_not awaiting_consent?
    assert code_from.present?
  end

  test "prompt=consent asks even when the client's consent is switched off" do
    sign_in_as(@owner)
    connect
    registration = redeem(approve!)
    within(@tenant) { Client.find_by!(client_id: registration["client_id"]).update!(consent_required: false) }

    authorize(
      client_id: registration["client_id"],
      redirect_uri: REDIRECT_URI,
      scope: SCOPE,
      prompt: "consent"
    )

    assert awaiting_consent?
  end

  test "prompt=consent still asks an approved client's caller" do
    sign_in_as(@owner)
    connect
    registration = redeem(approve!)

    authorize(
      client_id: registration["client_id"],
      redirect_uri: REDIRECT_URI,
      scope: SCOPE,
      prompt: "consent"
    )

    assert awaiting_consent?
  end

  test "the client the wizard created signs the owner in, carrying the scopes it was approved for" do
    sign_in_as(@owner)
    connect
    registration = redeem(approve!)

    authorize(
      client_id: registration["client_id"],
      redirect_uri: REDIRECT_URI,
      scope: SCOPE,
      resource: RESOURCE
    )
    consent! if awaiting_consent?

    granted = token(
      grant_type: "authorization_code",
      code: code_from,
      redirect_uri: REDIRECT_URI,
      code_verifier: verifier,
      client_id: registration["client_id"],
      client_secret: registration["client_secret"]
    )

    claims = claims_in(granted["access_token"])

    assert_equal [ RESOURCE ], Array(claims["aud"])
    assert_includes Scopes.list(claims["scope"]), "uris:catalog:read"
  end

  test "the endpoint an app sends a person to is the one discovery advertises" do
    get "/.well-known/openid-configuration"

    advertised = JSON.parse(response.body)["handshake_endpoint"]

    assert_equal "#{issuer_for(@tenant).url}/handshake", advertised

    sign_in_as(@owner)
    connect

    assert_response :success
  end

  private

    def redirected_uri
      URI.parse(response.location)
    end
end
