require "test_helper"

class PairingTest < ActionDispatch::IntegrationTest
  APP = "https://jons.things.test".freeze
  RESOURCE = "#{APP}/mcp".freeze
  RETURN_TO = "#{APP}/setup/callback".freeze
  REDIRECT_URI = "#{APP}/auth/masks/callback".freeze
  SCOPE = "openid profile email offline_access things:read".freeze

  setup do
    @owner = create_actor(@tenant, nickname: "owner", password: "password")
    host! host_for(@tenant)
  end

  def connect(redirect_uris: [ REDIRECT_URI ], **overrides)
    params = {
      client_name: "things",
      resource: RESOURCE,
      scope: SCOPE,
      return_to: RETURN_TO,
      state: "app-state"
    }.merge(overrides).compact

    query = params.to_a
    Array(redirect_uris).each { |uri| query << [ "redirect_uris", uri ] }

    get "/setup/connect?#{URI.encode_www_form(query)}"
  end

  def approve!
    post "/setup/connect", params: { approve: "yes" }
    redirected["initial_access_token"]
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

  def paired
    within(@tenant) { Client.approved.sole }
  end

  test "a signed-in owner is shown what is being connected, and where it will be sent back" do
    sign_in_as(@owner)
    connect

    assert_response :success
    assert_match "Connect things?", response.body
    assert_match APP, response.body
    assert_match "things:read", response.body
    assert_match REDIRECT_URI, response.body
  end

  test "approving mints a one-time token, and carries the app's state back with it" do
    sign_in_as(@owner)
    connect
    secret = approve!

    assert_equal "#{APP}/setup/callback", redirected_uri.to_s.split("?").first
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
    assert_equal paired.client_id, registration["client_id"]
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
    assert_equal "things", registration["client_name"]
    assert_equal Scopes.list(SCOPE), Scopes.list(registration["scope"])
    assert_equal [ RESOURCE ], paired.resources
  end

  test "an approved client is not a dynamic one, and records who approved it" do
    sign_in_as(@owner)
    connect
    approve!

    assert_not paired.dynamic
    assert paired.approved?
    assert_equal @owner.id, paired.approved_by_id
  end

  test "approving grants the actor the scopes the app asked for" do
    sign_in_as(@owner)
    connect
    approve!

    assert_includes within(@tenant) { @owner.reload.scope_list }, "things:read"
  end

  test "declining connects nothing and says so to the app" do
    sign_in_as(@owner)
    connect

    post "/setup/connect", params: { deny: "yes" }

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

    get "/setup/connect"

    assert_response :bad_request
    assert_match "no connection request is in progress", response.body
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

  test "a token minted for one tenant registers nothing at another" do
    sign_in_as(@owner)
    connect
    secret = approve!

    reset!
    host! host_for(@other)
    redeem(secret)

    assert_response :unauthorized
    assert_equal 0, within(@other) { Client.count }
  end

  test "the setup prompt runs first when nobody has an account yet, and comes back here" do
    within(@tenant) { @owner.destroy! }

    connect

    assert_redirected_to login_path

    post "/login",
         params: { event: "setup", nickname: "owner", password: "a-long-enough-password" },
         as: :json

    assert_equal "/setup/connect", JSON.parse(response.body)["redirectTo"]

    get "/setup/connect"

    assert_response :success
    assert_match "Connect things?", response.body
  end

  test "an approved client does not ask again for what a person already approved" do
    sign_in_as(@owner)
    connect
    registration = redeem(approve!)

    authorize(client_id: registration["client_id"], redirect_uri: REDIRECT_URI, scope: SCOPE)

    assert_not awaiting_consent?
    assert code_from.present?
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
    assert_includes Scopes.list(claims["scope"]), "things:read"
  end

  private

    def redirected_uri
      URI.parse(response.location)
    end
end
