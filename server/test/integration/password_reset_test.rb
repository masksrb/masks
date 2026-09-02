require "test_helper"

class PasswordResetTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    host! host_for(@tenant)

    @actor = create_actor(@tenant, email: "owner@example.com")
  end

  def with_mailer(from: "masks@example.com")
    held = Rails.configuration.masks.mail_from
    Rails.configuration.masks.mail_from = from
    yield
  ensure
    Rails.configuration.masks.mail_from = held
  end

  def ask_to_reset(identifier = @actor.nickname)
    post "/login", params: { event: "identify", identifier: identifier }, as: :json
    post "/login", params: { event: "forgot-password" }, as: :json

    JSON.parse(response.body)
  end

  def open_reset(actor = @actor)
    within(@tenant) { PasswordReset.open!(actor: actor) }
  end

  test "asking to reset says the same thing whether or not the account exists" do
    with_mailer do
      known = ask_to_reset
      known_mail = enqueued_jobs.count

      clear_enqueued_jobs

      unknown = ask_to_reset("no-such-account")

      assert_equal known["prompt"], unknown["prompt"]
      assert_equal known["warnings"], unknown["warnings"]
      assert_includes known["warnings"], "reset-sent"
      assert_equal 1, known_mail
      assert_equal 0, enqueued_jobs.count
    end
  end

  test "with no mailer the server says so rather than pretending it sent one" do
    body = ask_to_reset

    assert_includes body["warnings"], "no-mailer"
    refute_includes body["warnings"], "reset-sent"
  end

  test "the link sets a new password and signs them in" do
    reset = open_reset

    get "/reset/#{reset.secret}"
    assert_redirected_to login_path

    post "/login", params: { event: "reset-password", password: "a-new-password" }, as: :json
    body = JSON.parse(response.body)

    assert_equal "settled", body["prompt"]

    within(@tenant) do
      assert_equal @actor, Actor.authenticate(@actor.nickname, "a-new-password")
      assert_nil Actor.authenticate(@actor.nickname, "password")
    end
  end

  test "resetting signs out every existing session and refresh token" do
    session = within(@tenant) { Session.start!(actor: @actor) }
    refresh = within(@tenant) do
      RefreshToken.mint!(actor: @actor, client: create_client(@tenant), expires_at: 1.day.from_now)
    end

    reset = open_reset

    get "/reset/#{reset.secret}"
    post "/login", params: { event: "reset-password", password: "a-new-password" }, as: :json

    within(@tenant) do
      assert_not_nil session.reload.revoked_at
      assert refresh.reload.consumed?
    end
  end

  test "a reset does not get past a second factor" do
    enable_otp(@actor, @tenant)

    reset = open_reset

    get "/reset/#{reset.secret}"
    post "/login", params: { event: "reset-password", password: "a-new-password" }, as: :json

    assert_equal "second-factor", JSON.parse(response.body)["prompt"]
  end

  test "a reset link works once" do
    reset = open_reset

    get "/reset/#{reset.secret}"
    post "/login", params: { event: "reset-password", password: "a-new-password" }, as: :json

    get "/reset/#{reset.secret}"
    assert_response :gone
  end

  test "a short password is refused and the link survives it" do
    reset = open_reset

    get "/reset/#{reset.secret}"
    post "/login", params: { event: "reset-password", password: "short" }, as: :json
    body = JSON.parse(response.body)

    assert_equal "reset-password", body["prompt"]
    assert_includes body["warnings"], "short-password"

    within(@tenant) { assert reset.reload.live? }
  end

  test "opening a reset retires any earlier one" do
    first = open_reset
    open_reset

    get "/reset/#{first.secret}"
    assert_response :gone
  end

  test "an invited account that never accepted cannot be recovered into" do
    invited = within(@tenant) { Actor.invite!(nickname: "sam", email: "sam@example.com") }

    with_mailer do
      assert_not within(@tenant) { Recoveries.request(identifier: "sam") }
      assert_equal 0, enqueued_jobs.count
      assert_not within(@tenant) { invited.reload }.activated?
    end
  end

  test "a reset link from another tenant is not valid here" do
    reset = open_reset

    host! host_for(@other)
    get "/reset/#{reset.secret}"

    assert_response :gone
  end

  test "a mailed reset verifies the email, one handed over by an admin does not" do
    within(@tenant) do
      @actor.update!(email_verified_at: nil)

      mailed = PasswordReset.open!(actor: @actor)
      mailed.delivered!
      PasswordReset.settle!(mailed.secret, "a-new-password")

      assert @actor.reload.email_verified_at.present?

      @actor.update!(email_verified_at: nil)

      copied = PasswordReset.open!(actor: @actor)
      PasswordReset.settle!(copied.secret, "another-password")

      assert_nil @actor.reload.email_verified_at
    end
  end

  test "changing a password in the account page keeps the session that changed it" do
    sign_in_as(@actor)
    held = within(@tenant) { Session.live.order(:id).last }

    patch "/account/password",
          params: { current_password: "password", password: "a-new-password" }

    assert_redirected_to root_path

    within(@tenant) do
      assert_nil held.reload.revoked_at
      assert_equal @actor, Actor.authenticate(@actor.nickname, "a-new-password")
    end
  end

  test "changing a password refuses without the current one" do
    sign_in_as(@actor)

    patch "/account/password",
          params: { current_password: "wrong", password: "a-new-password" }

    assert_equal "That is not your current password.", flash[:alert]

    within(@tenant) { assert_equal @actor, Actor.authenticate(@actor.nickname, "password") }
  end

  test "changing a password signs out the other sessions" do
    other = within(@tenant) { Session.start!(actor: @actor) }

    sign_in_as(@actor)
    patch "/account/password",
          params: { current_password: "password", password: "a-new-password" }

    within(@tenant) { assert_not_nil other.reload.revoked_at }
  end
end
