require "test_helper"

class ConsentTest < ActionDispatch::IntegrationTest
  setup do
    @actor = create_actor(email: "owner@probe.example.com", name: "Owner")
    @registration = register
    host! host_for(@tenant)
  end

  test "consent is asked once and remembered after that" do
    authorized_code(actor: @actor, registration: @registration)

    authorize(client_id: @registration["client_id"])

    assert response.redirect?
    assert code_from.present?
  end

  test "prompt=consent asks again even when it was remembered" do
    authorized_code(actor: @actor, registration: @registration)

    authorize(client_id: @registration["client_id"], prompt: "consent")

    assert_redirected_to consent_path
  end

  test "consent granted for a narrow scope does not cover a wider one" do
    authorized_code(actor: @actor, registration: @registration, scope: "openid")

    authorize(client_id: @registration["client_id"], scope: "openid profile email")

    assert_redirected_to consent_path
  end

  test "declining sends access_denied back to the client" do
    sign_in_as(@actor)
    authorize(client_id: @registration["client_id"], state: "opaque")

    post "/consent", params: { deny: "yes" }

    assert_equal "access_denied", redirected["error"]
    assert_equal "opaque", redirected["state"]
  end

  test "prompt=login re-authenticates a signed-in actor" do
    authorized_code(actor: @actor, registration: @registration)

    authorize(client_id: @registration["client_id"], prompt: "login")

    assert_redirected_to login_path
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

    authorize(client_id: @registration["client_id"], prompt: "none")

    assert code_from.present?
    assert_nil redirected["error"]
  end

  test "the consent screen names the client and the scopes it asks for" do
    sign_in_as(@actor)
    authorize(client_id: @registration["client_id"])
    follow_redirect!

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

    assert_redirected_to consent_path
  end

  test "the consent screen is not reachable without a pending authorization" do
    sign_in_as(@actor)

    get "/consent"

    assert_redirected_to root_path
  end
end
