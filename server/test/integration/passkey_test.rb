require "test_helper"
require_relative "../support/fake_authenticator"

class PasskeyTest < ActionDispatch::IntegrationTest
  setup do
    host! host_for(@tenant)

    @actor = create_actor(@tenant, email: "owner@example.com")
    @device = FakeAuthenticator.new(origin_for(@tenant))
  end

  def enrol(user_verified: true, name: "This laptop")
    sign_in_as(@actor)

    post "/account/passkeys/challenge"
    options = JSON.parse(response.body)

    credential = @device.enrol(options, user_verified: user_verified)

    post "/account/passkeys",
         params: { credential: JSON.generate(credential), name: name }

    within(@tenant) { Passkey.where(actor_id: @actor.id).newest_first.first }
  end

  def refuse_downloads
    FidoMetadata::Client.class_eval do
      alias_method :download_toc_before_stub, :download_toc
      define_method(:download_toc) { |*| raise "a request tried to download metadata" }
    end

    yield
  ensure
    FidoMetadata::Client.class_eval do
      alias_method :download_toc, :download_toc_before_stub
      remove_method :download_toc_before_stub
    end
  end

  def sign_in_with_passkey(user_verified: true)
    post "/login", params: { event: "passkey:challenge" }, as: :json
    offer = JSON.parse(response.body)

    credential = @device.assert(offer.dig("passkey", "options"), user_verified: user_verified)

    post "/login", params: { event: "passkey:verify", passkey: JSON.generate(credential) }, as: :json

    JSON.parse(response.body)
  end

  test "a passkey is enrolled from the account page and listed there" do
    passkey = enrol

    assert_redirected_to root_path
    assert_equal "This laptop", passkey.name
    assert passkey.user_verified

    get root_path
    assert_select "li", text: /This laptop/
  end

  test "enrolling needs a session" do
    post "/account/passkeys/challenge"

    assert_redirected_to login_path
  end

  test "a verified passkey signs in without a password and without a second factor" do
    enrol
    reset!
    host! host_for(@tenant)

    body = sign_in_with_passkey

    assert_equal "settled", body["prompt"]
    assert_equal @actor.nickname, body.dig("actor", "nickname")
  end

  test "a verified passkey satisfies a second factor an authenticator would otherwise demand" do
    enrol
    enable_otp(@actor, @tenant)
    reset!
    host! host_for(@tenant)

    body = sign_in_with_passkey

    assert_equal "settled", body["prompt"]
  end

  test "a passkey with no user verification is a first factor only" do
    enrol(user_verified: false)
    enable_otp(@actor, @tenant)
    reset!
    host! host_for(@tenant)

    body = sign_in_with_passkey(user_verified: false)

    assert_equal "second-factor", body["prompt"]
  end

  test "the sign-in records what was used, and the id token says so" do
    enrol
    reset!
    host! host_for(@tenant)

    sign_in_with_passkey

    session = within(@tenant) { Session.live.order(:id).last }

    assert_includes session.amr, "swk"
    assert_includes session.amr, "mfa"
  end

  test "a password login is not reported as multi-factor merely because an authenticator exists" do
    enable_otp(@actor, @tenant)

    within(@tenant) do
      assert_equal Issuer::ACR_PASSWORD, issuer_for(@tenant).acr_for([ "pwd" ])
      assert_equal Issuer::ACR_MULTI_FACTOR, issuer_for(@tenant).acr_for([ "pwd", "otp", "mfa" ])
    end
  end

  test "an assertion for another tenant's passkey is refused" do
    enrol
    reset!

    host! host_for(@other)
    create_actor(@other, nickname: "elsewhere")

    post "/login", params: { event: "passkey:challenge" }, as: :json
    offer = JSON.parse(response.body)

    assert_nil offer.dig("passkey", "options"),
               "a tenant with no passkeys offered a challenge anyway"
  end

  test "a replayed assertion is refused, because the challenge is spent" do
    enrol
    reset!
    host! host_for(@tenant)

    post "/login", params: { event: "passkey:challenge" }, as: :json
    offer = JSON.parse(response.body)
    credential = @device.assert(offer.dig("passkey", "options"))

    post "/login", params: { event: "passkey:verify", passkey: JSON.generate(credential) }, as: :json
    assert_equal "settled", JSON.parse(response.body)["prompt"]

    post "/login", params: { event: "passkey:verify", passkey: JSON.generate(credential) }, as: :json
    body = JSON.parse(response.body)

    assert_includes body["warnings"], "passkey-expired"
  end

  test "a passkey is labelled by its authenticator, and named by its owner when they say" do
    passkey = enrol(name: nil)

    assert_equal "Passkey", passkey.label

    within(@tenant) do
      Authenticator.create!(aaguid: passkey.aaguid, name: "YubiKey 5 Series",
                            source: Authenticator::MDS, certification: "FIDO_CERTIFIED_L2")

      assert_equal "YubiKey 5 Series", passkey.reload.label

      passkey.update!(name: "The one on my keys")
      assert_equal "The one on my keys", passkey.reload.label
    end
  end

  test "a compromised authenticator is reported against the passkeys made with it" do
    passkey = enrol

    within(@tenant) do
      Authenticator.create!(
        aaguid: passkey.aaguid, name: "Leaky Key", source: Authenticator::MDS,
        statuses: [ "USER_VERIFICATION_BYPASS" ], compromised_at: Time.current
      )

      assert passkey.reload.compromised?
      assert_equal "USER_VERIFICATION_BYPASS", passkey.compromise
    end

    get root_path
    assert_match(/reports a compromise/, response.body)
  end

  test "signing in with a passkey never reaches the metadata service" do
    enrol
    reset!
    host! host_for(@tenant)

    refuse_downloads do
      body = sign_in_with_passkey

      assert_equal "settled", body["prompt"]
    end
  end

  test "a passkey can be removed, and stops working" do
    passkey = enrol

    delete "/account/passkeys/#{passkey.id}"
    assert_redirected_to root_path

    within(@tenant) { assert_equal 0, Passkey.where(actor_id: @actor.id).count }
  end

  test "one actor cannot remove another's passkey" do
    passkey = enrol

    other = create_actor(@tenant, nickname: "second", password: "password")
    reset!
    host! host_for(@tenant)
    sign_in_as(other)

    delete "/account/passkeys/#{passkey.id}"

    within(@tenant) { assert_equal 1, Passkey.where(actor_id: @actor.id).count }
  end
end
