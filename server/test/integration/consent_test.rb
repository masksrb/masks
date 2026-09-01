require "test_helper"

class ConsentTest < ActionDispatch::IntegrationTest
  setup do
    @actor = create_actor(email: "owner@probe.example.com", name: "Owner")
    @registration = register
    host! host_for(@tenant)
  end

  test "consent is asked once and remembered after that" do
    authorized_code(actor: @actor, registration: @registration)

    authorize(client_id: @registration["client_id"], state: "again")

    assert response.redirect?
    assert code_from.present?
  end

  test "prompt=consent asks again even when it was remembered" do
    authorized_code(actor: @actor, registration: @registration)

    authorize(client_id: @registration["client_id"], prompt: "consent")

    assert awaiting_consent?
  end

  test "prompt=consent is satisfied by approving it once, and does not loop" do
    authorized_code(actor: @actor, registration: @registration)

    authorize(client_id: @registration["client_id"], prompt: "consent", state: "again")
    consent!

    assert code_from.present?
  end

  test "consent granted for a narrow scope does not cover a wider one" do
    authorized_code(actor: @actor, registration: @registration, scope: "openid")

    authorize(client_id: @registration["client_id"], scope: "openid profile email")

    assert awaiting_consent?
  end

  test "declining sends access_denied back to the client" do
    sign_in_as(@actor)
    authorize(client_id: @registration["client_id"], state: "opaque")

    decline!

    assert_equal "access_denied", redirected["error"]
    assert_equal "opaque", redirected["state"]
  end

  test "prompt=login re-authenticates a signed-in actor" do
    authorized_code(actor: @actor, registration: @registration)

    authorize(client_id: @registration["client_id"], prompt: "login")

    assert awaiting_login?
    assert_equal "first-factor", auth_data["prompt"]
  end

  test "prompt=login is satisfied by authenticating again, and does not loop" do
    authorized_code(actor: @actor, registration: @registration)

    authorize(client_id: @registration["client_id"], prompt: "login", state: "again")
    advance!("password", password: "password")

    assert code_from.present?
  end

  test "reauthenticating moves auth_time forward even when the session is reused" do
    authorized_code(actor: @actor, registration: @registration)

    signed_in_at = within { Session.live.first.authenticated_at }

    travel 5.seconds

    authorize(client_id: @registration["client_id"], prompt: "login", state: "again")
    advance!("password", password: "password")

    minted = within { AuthorizationCode.order(:created_at).last.authenticated_at }

    assert_operator minted, :>, signed_in_at,
                    "the code carried the old session's auth_time after a fresh first factor"
  end

  test "prompt=none refuses to interact when nobody is signed in" do
    authorize(client_id: @registration["client_id"], prompt: "none")

    assert_equal "interaction_required", redirected["error"]
  end

  test "prompt=none refuses to interact when consent has not been given" do
    sign_in_as(@actor)

    authorize(client_id: @registration["client_id"], prompt: "none")

    assert_equal "interaction_required", redirected["error"]
  end

  test "prompt=none succeeds once sign-in and consent are settled" do
    authorized_code(actor: @actor, registration: @registration)

    authorize(client_id: @registration["client_id"], prompt: "none", state: "again")

    assert code_from.present?
    assert_nil redirected["error"]
  end

  test "the consent screen names the client and the scopes it asks for" do
    sign_in_as(@actor)
    authorize(client_id: @registration["client_id"])

    assert_response :success
    assert_match @registration["client_name"], response.body
    assert_match "Read your email address", response.body
  end

  test "consent given by one actor does not carry to another" do
    authorized_code(actor: @actor, registration: @registration)

    stranger = create_actor(nickname: "stranger")
    reset!
    host! host_for(@tenant)
    sign_in_as(stranger)

    authorize(client_id: @registration["client_id"])

    assert awaiting_consent?
  end

  test "max_age forces a fresh first factor when the session is older" do
    authorized_code(actor: @actor, registration: @registration)

    within { Session.live.each { |record| record.update!(authenticated_at: 10.minutes.ago) } }

    authorize(client_id: @registration["client_id"], max_age: 60)

    assert awaiting_login?
    assert_equal "first-factor", auth_data["prompt"]
  end
end
