require "test_helper"
require_relative "../support/fake_authenticator"

class PasskeySignupTest < ActionDispatch::IntegrationTest
  setup do
    host! host_for(@tenant)

    create_actor(@tenant, nickname: "owner", scopes: "openid masks:manage")
    @device = FakeAuthenticator.new(origin_for(@tenant))
  end

  def policy!(**attributes)
    within(@tenant) do
      SignInPolicy.create!({ key: "passkeys", name: "Passkeys", signup: true, first_factors: [ "passkey" ],
                             second_factors: [ "passkey" ] }.merge(attributes))
    end.tap { |held| @tenant.update!(sign_in_policy: held) }
  end

  def event(name, **params)
    post "/login", params: { event: name, **params }, as: :json

    JSON.parse(response.body)
  end

  def detailed
    event("identify", identifier: "ada@example.com")
    event("signup", nickname: "ada", email: "ada@example.com")
  end

  def create_passkey(user_verified: true)
    options = event("signup:passkey-challenge").dig("signup", "passkeyOptions")
    credential = @device.enrol(options, user_verified: user_verified)

    event("signup:passkey", passkey: JSON.generate(credential))
  end

  def created
    within(@tenant) { Actor.find_by(nickname: "ada") }
  end

  test "a policy offering only passkeys opens signup, and asks for a passkey instead of a password" do
    policy!

    assert event("identify", identifier: "ada@example.com")["signupOpen"]

    body = event("signup", nickname: "ada", email: "ada@example.com")

    assert_equal "signup-credentials", body["prompt"]
    assert_equal({ "password" => false, "passkey" => true }, body.dig("signup", "credentials"))
  end

  test "the passkey made at signup is discoverable and checks who you are" do
    policy!
    detailed

    options = event("signup:passkey-challenge").dig("signup", "passkeyOptions")

    assert_equal "required", options.dig("authenticatorSelection", "residentKey")
    assert_equal "required", options.dig("authenticatorSelection", "userVerification")
    assert_equal "ada@example.com", options.dig("user", "name")
  end

  test "an account made with a passkey has no password, and is signed in with both factors" do
    policy!
    detailed

    body = create_passkey

    assert body["settled"], body["prompt"]
    refute created.password?
    assert created.activated?
    assert_equal 1, within(@tenant) { created.passkeys.count }

    within(@tenant) do
      session = Session.live.where(actor: created).sole

      assert_includes session.amr, "swk"
      assert_includes session.amr, "mfa"
    end
  end

  test "the passkey signs the new account back in" do
    policy!
    detailed
    create_passkey

    reset!
    host! host_for(@tenant)

    offer = event("passkey:challenge")
    credential = @device.assert(offer.dig("passkey", "options"))
    body = event("passkey:verify", passkey: JSON.generate(credential))

    assert body["settled"], body["prompt"]
    assert_equal "ada", body.dig("actor", "nickname")
  end

  test "a passkey that does not check who you are cannot open an account" do
    policy!
    detailed

    body = create_passkey(user_verified: false)

    assert_includes body["warnings"], "passkey-unverified"
    assert_nil created
  end

  test "a password is refused where the policy offers only passkeys" do
    policy!
    detailed

    body = event("signup", password: "a-long-enough-password", password_confirmation: "a-long-enough-password")

    assert_includes body["warnings"], "factor-not-offered"
    assert_nil created
  end

  test "a passkey is refused where the policy offers only passwords" do
    policy!(first_factors: [ "password" ], second_factors: [ "backup_codes" ])
    detailed

    body = event("signup:passkey-challenge")

    assert_includes body["warnings"], "factor-not-offered"
    assert_nil body.dig("signup", "passkeyOptions")
  end

  test "a challenge answered once cannot open a second account" do
    policy!
    detailed

    options = event("signup:passkey-challenge").dig("signup", "passkeyOptions")
    credential = JSON.generate(@device.enrol(options))

    assert event("signup:passkey", passkey: credential)["settled"]

    reset!
    host! host_for(@tenant)
    event("identify", identifier: "eve@example.com")
    event("signup", nickname: "eve", email: "eve@example.com")

    body = event("signup:passkey", passkey: credential)

    assert_includes body["warnings"], "passkey-expired"
    assert_nil within(@tenant) { Actor.find_by(nickname: "eve") }
  end

  test "the only passkey on an account without a password cannot be removed" do
    policy!
    detailed
    create_passkey

    passkey = within(@tenant) { created.passkeys.sole }

    delete "/account/passkeys/#{passkey.id}"

    assert_equal I18n.t("passkeys.last_way_in"), flash[:alert]
    assert within(@tenant) { Passkey.exists?(passkey.id) }
  end

  test "the account page has no password form for an account without one" do
    policy!
    detailed
    create_passkey

    get root_path

    assert_select "#change-password", false
    assert_select "#password .aside", text: I18n.t("account.index.password.none")
  end
end
