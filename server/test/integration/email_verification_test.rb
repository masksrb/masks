require "test_helper"

class EmailVerificationTest < ActionDispatch::IntegrationTest
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

  def open_verification(actor = @actor)
    within(@tenant) { EmailVerification.open!(actor: actor) }
  end

  test "the link confirms the address and says so" do
    verification = open_verification

    get "/verify/#{verification.secret}"

    assert_response :success
    assert_match "is confirmed", response.body
    assert_match @actor.email, response.body

    within(@tenant) { assert @actor.reload.email_verified_at.present? }
  end

  test "a confirmation link works once" do
    verification = open_verification

    get "/verify/#{verification.secret}"
    get "/verify/#{verification.secret}"

    assert_response :gone
  end

  test "a link stops working when the address it names is no longer the one on file" do
    verification = open_verification

    within(@tenant) { @actor.update!(email: "moved@example.com") }

    get "/verify/#{verification.secret}"

    assert_response :gone
    within(@tenant) { assert_nil @actor.reload.email_verified_at }
  end

  test "confirming requires no session, since the mailbox is the proof" do
    verification = open_verification

    get "/verify/#{verification.secret}"

    assert_response :success
    within(@tenant) { assert @actor.reload.email_verified_at.present? }
  end

  test "a link from another tenant is not valid here" do
    verification = open_verification

    host! host_for(@other)
    get "/verify/#{verification.secret}"

    assert_response :gone
  end

  test "the owner is sent a confirmation at first run when there is a mailer" do
    fresh = Tenant.create!(subdomain: "fresh-#{SecureRandom.hex(4)}", name: "Fresh")
    host! host_for(fresh)

    with_mailer do
      post "/login", params: {
        event: "setup", nickname: "owner",
        email: "owner@example.invalid", password: "a-long-enough-password"
      }, as: :json

      assert JSON.parse(response.body)["settled"]

      Tenant.switch(fresh) do
        actor = Actor.sole

        assert_nil actor.email_verified_at
        assert EmailVerification.where(actor_id: actor.id).live.any?
      end
    end

    assert_equal 1, enqueued_jobs.count { |job| job[:args].first == "ActorMailer" }
  end

  test "an account page asks for a confirmation, and refuses once confirmed" do
    with_mailer do
      sign_in_as(@actor)

      post "/account/verify"
      assert_match(/on its way/, flash[:notice])

      within(@tenant) { @actor.update!(email_verified_at: Time.current) }

      post "/account/verify"
      assert_equal "That address is already confirmed.", flash[:alert]
    end
  end

  test "nothing is opened for an address already confirmed" do
    within(@tenant) { @actor.update!(email_verified_at: Time.current) }

    with_mailer do
      within(@tenant) do
        assert_equal({ delivered: false, url: nil }, Verifications.open(actor: @actor))
        assert_equal 0, EmailVerification.where(actor_id: @actor.id).count
      end
    end
  end

  test "nothing is opened for an account with no address" do
    plain = create_actor(@tenant, nickname: "noaddress")

    with_mailer do
      within(@tenant) do
        assert_equal({ delivered: false, url: nil }, Verifications.open(actor: plain))
        assert_equal 0, EmailVerification.where(actor_id: plain.id).count
      end
    end
  end
end
