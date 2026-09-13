require "test_helper"

class SignupTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  PASSWORD = "a-long-enough-password".freeze

  setup do
    host! host_for(@tenant)

    @owner = create_actor(@tenant, nickname: "owner", scopes: "openid masks:manage")
    ActionMailer::Base.deliveries.clear
    Adapters::SmsLog.deliveries.clear
  end

  def with_mailer(from: "masks@example.com")
    held = Rails.configuration.masks.mail_from
    Rails.configuration.masks.mail_from = from
    yield
  ensure
    Rails.configuration.masks.mail_from = held
  end

  def policy!(**attributes)
    within(@tenant) do
      SignInPolicy.create!({ key: "open", name: "Open", signup: true, second_factors: [ "backup_codes" ] }.merge(attributes))
    end.tap { |held| @tenant.update!(sign_in_policy: held) }
  end

  def event(name, **params)
    perform_enqueued_jobs do
      post "/login", params: { event: name, **params }, as: :json
    end

    JSON.parse(response.body)
  end

  def sign_up(identifier: "ada@example.com", nickname: "ada", email: "ada@example.com", **details)
    event("identify", identifier: identifier)
    event("signup", nickname: nickname, email: email, **details)
    event("signup", password: PASSWORD, password_confirmation: PASSWORD)
  end

  def mailed_code
    ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
  end

  def texted_code
    Adapters::SmsLog.deliveries.last[:body][/\b\d{6}\b/]
  end

  def created
    within(@tenant) { Actor.find_by(nickname: "ada") }
  end

  test "with signup closed, an unknown identifier looks exactly like a known one" do
    known = event("identify", identifier: "owner")
    reset!
    host! host_for(@tenant)
    unknown = event("identify", identifier: "nobody@example.com")

    assert_equal known["prompt"], unknown["prompt"]
    refute unknown["signupOpen"]
  end

  test "with signup open, an unknown address is taken through details and a password, and signed in" do
    policy!

    body = event("identify", identifier: "ada@example.com")

    assert_equal "signup", body["prompt"]
    assert_equal "ada@example.com", body.dig("signup", "email")
    assert_equal %w[identification credentials], body.dig("signup", "steps")

    body = event("signup", nickname: "ada", email: "ada@example.com", name: "Ada Lovelace")

    assert_equal "signup-password", body["prompt"]
    assert_nil created

    body = event("signup", password: PASSWORD, password_confirmation: PASSWORD)

    assert body["settled"], body["prompt"]
    assert_equal Scopes::STANDARD.sort, created.scope_list.sort
    refute created.manages?
    assert created.signed_up_at
  end

  test "a known identifier still asks for its password, signup open or not" do
    policy!

    assert_equal "first-factor", event("identify", identifier: "owner")["prompt"]
  end

  test "signup never makes a manager, and holds only the scopes the policy names" do
    policy!(signup_scopes: "openid email")

    sign_up

    assert_equal %w[email openid], created.scope_list.sort
  end

  test "an address outside the allowed domains is not offered signup" do
    policy!(email_domains: [ "example.org" ])

    assert_equal "first-factor", event("identify", identifier: "ada@example.com")["prompt"]

    event("identify", identifier: "ada")
    body = event("signup", nickname: "ada", email: "ada@example.com")

    assert_includes body["warnings"], "signup-domain-refused"
  end

  test "the password follows the policy: long enough, and not a common one" do
    policy!(password_minimum: 12)

    event("identify", identifier: "ada@example.com")
    event("signup", nickname: "ada", email: "ada@example.com")

    assert_includes event("signup", password: "short-pass", password_confirmation: "short-pass")["warnings"],
                    "short-password"
    assert_includes event("signup", password: "password1234", password_confirmation: "password1234")["warnings"],
                    "common-password"
    assert_nil created
  end

  test "a policy that requires a second factor stops a new account at enrolment" do
    policy!(second_factors: %w[otp backup_codes], second_factor_required: true)

    body = sign_up

    assert_equal "enrol", body["prompt"]
    assert body.dig("enrolment", "required")
    refute body.dig("enrolment", "offers", "passkey")
  end

  test "a policy that offers second factors offers them once, and they can be skipped" do
    policy!(second_factors: %w[otp passkey backup_codes])

    body = sign_up

    assert_equal "enrol", body["prompt"]
    refute body.dig("enrolment", "required")

    assert event("enrol:done")["settled"]
  end

  test "a policy asking for a phone collects it, and refuses one that is not international" do
    policy!(phone: "required")

    event("identify", identifier: "ada@example.com")

    body = event("signup", nickname: "ada", email: "ada@example.com", phone: "555 1234")

    assert_includes body["warnings"], "invalid-phone"

    event("signup", nickname: "ada", email: "ada@example.com", phone: "+1 (555) 123-4567")
    event("signup", password: PASSWORD, password_confirmation: PASSWORD)

    assert_equal "+15551234567", created.phone
  end

  test "confirming by code holds the account at the confirmation tab until the code is entered" do
    with_mailer do
      policy!(confirmation: "code")

      body = sign_up

      assert_equal "confirm-email", body["prompt"]
      assert_equal %w[identification credentials confirmation], body.dig("confirmation", "steps")
      assert body.dig("confirmation", "signingUp")
      assert_nil created.email_verified_at

      body = event("confirm:email", code: "000000")

      assert_includes body["warnings"], "invalid-code"

      body = event("confirm:email", code: mailed_code)

      assert body["settled"], body["prompt"]
      assert created.email_verified_at
    end
  end

  test "a code stops working after too many wrong guesses" do
    with_mailer do
      policy!(confirmation: "code")
      sign_up
      code = mailed_code

      within(@tenant) do
        token = ConfirmationCode.where(actor_id: created.id).live.sole

        ConfirmationCode::ATTEMPTS.times { token.reload.verify("000000") }

        refute token.reload.verify(code)
        assert token.consumed?
      end

      assert_nil created.email_verified_at
    end
  end

  test "an unconfirmed account is asked again the next time it signs in" do
    with_mailer do
      policy!(confirmation: "code")
      sign_up
      reset!
      host! host_for(@tenant)

      event("identify", identifier: "ada")
      body = event("password", password: PASSWORD)

      assert_equal "confirm-email", body["prompt"]
    end
  end

  test "confirming by link waits until the link is opened" do
    with_mailer do
      policy!(confirmation: "link")

      body = sign_up

      assert_equal "confirm-email", body["prompt"]
      assert_equal "link", body.dig("confirmation", "mode")

      within(@tenant) { created.update!(email_verified_at: Time.current) }

      assert event("confirm:check")["settled"]
    end
  end

  test "an account waiting for approval cannot sign in until a manager approves it" do
    with_mailer do
      within(@tenant) { @owner.update!(email_verified_at: Time.current) }
      policy!(confirmation: "approval")

      body = sign_up

      assert_equal "awaiting-approval", body["prompt"]
      assert created.pending_approval_at
      assert(ActionMailer::Base.deliveries.any? { |mail| mail.to == [ @owner.email ] })

      within(@tenant) { Confirmations.approve!(created, by: @owner) }

      assert event("confirm:check")["settled"]
      assert(ActionMailer::Base.deliveries.any? { |mail| mail.to == [ "ada@example.com" ] })
    end
  end

  test "a policy requiring a confirmed phone texts a code through the primary adapter" do
    within(@tenant) { Adapters::SmsLog.create!(key: "log", name: "Log", primary: true) }
    policy!(phone: "required", phone_verified: true)

    body = sign_up(phone: "+15551234567")

    assert_equal "confirm-phone", body["prompt"]
    assert_equal "+15551234567", Adapters::SmsLog.deliveries.last[:to]

    body = event("confirm:phone", code: texted_code)

    assert body["settled"], body["prompt"]
    assert created.phone_verified_at
  end

  test "an existing account missing a phone the policy now requires is asked for one" do
    policy!(phone: "required")

    event("identify", identifier: "owner")
    event("password", password: "password")
    body = event("otp", code: current_code(@owner))

    assert_equal "add-phone", body["prompt"]

    assert event("confirm:add-phone", phone: "+15557654321")["settled"]
    assert_equal "+15557654321", within(@tenant) { @owner.reload.phone }
  end

  test "a client's own policy is the one that applies" do
    registration = register(@tenant)
    own = within(@tenant) { SignInPolicy.create!(key: "own", name: "Own", signup: true, second_factors: [ "backup_codes" ]) }
    within(@tenant) { Client.find_by(client_id: registration["client_id"]).update!(sign_in_policy: own) }

    authorize(client_id: registration["client_id"])

    assert current_rid, "the authorize request is pending"

    post "/login", params: { event: "identify", identifier: "ada@example.com", rid: current_rid }, as: :json

    assert_equal "signup", JSON.parse(response.body)["prompt"]
  end
end
