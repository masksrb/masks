require "test_helper"

class NotificationEmailTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    host! host_for(@tenant)

    @actor = create_actor(@tenant, email: "owner@example.com", email_verified_at: Time.current)
  end

  def with_mailer(from: "masks@example.com")
    held = Rails.configuration.masks.mail_from
    Rails.configuration.masks.mail_from = from
    yield
  ensure
    Rails.configuration.masks.mail_from = held
  end

  def delivered
    perform_enqueued_jobs { yield }

    ActionMailer::Base.deliveries
  end

  def change_password!
    patch "/account/password", params: { current_password: "password", password: "hunter2hunter2" }
  end

  setup { ActionMailer::Base.deliveries.clear }

  test "a password change arrives as email with where and when it happened" do
    with_mailer do
      mail = delivered do
        sign_in_as(@actor)
        change_password!
      end.find { |sent| sent.subject.include?("Password changed") }

      assert mail, "no email announced the password change"
      assert_equal [ "owner@example.com" ], mail.to
      assert_includes mail.subject, "Demo"

      body = mail.text_part.body.to_s

      assert_includes body, "The password on your Demo account was changed."
      assert_includes body, "Recorded"
      assert_includes body, "If this was not you"
      assert_includes body, "#notifications"
    end
  end

  test "an action turned off on the account page stops arriving" do
    with_mailer do
      sign_in_as(@actor)

      patch "/account/notifications",
            params: { notifications: Notifications::MAILED - [ Event::PASSWORD_CHANGED ] }

      assert_redirected_to "#{root_path}#notifications"
      ActionMailer::Base.deliveries.clear

      subjects = delivered { change_password! }.map(&:subject)

      refute subjects.any? { |subject| subject.include?("Password changed") }
    end
  end

  test "the form cannot mute an action masks does not offer" do
    with_mailer do
      sign_in_as(@actor)

      patch "/account/notifications", params: { notifications: [ "", "avatar.uploaded", "../../etc" ] }

      within(@tenant) { assert_equal Notifications::MAILED.sort, @actor.reload.muted_notifications.sort }
    end
  end

  test "signing out is not somebody else's business to change" do
    patch "/account/notifications", params: { notifications: [] }

    assert_redirected_to login_path
    within(@tenant) { assert_empty @actor.reload.muted_notifications }
  end

  test "a first sign-in on a device is announced and the second is not" do
    with_mailer do
      first = delivered { sign_in_as(@actor) }
              .count { |sent| sent.subject.include?("Signed in") }

      ActionMailer::Base.deliveries.clear

      again = delivered { sign_in_as(@actor) }
              .count { |sent| sent.subject.include?("Signed in") }

      assert_equal 1, first
      assert_equal 0, again
    end
  end

  test "with no mailer configured a password change still works and mails nothing" do
    assert_empty delivered {
      sign_in_as(@actor)
      change_password!
    }
  end

  test "an unconfirmed address hears nothing" do
    with_mailer do
      within(@tenant) { @actor.update!(email_verified_at: nil) }

      assert_empty delivered {
        sign_in_as(@actor)
        change_password!
      }
    end
  end

  test "the account page offers every action masks can mail" do
    sign_in_as(@actor)
    get root_path

    Notifications::MAILED.each do |action|
      assert_select "input[type=checkbox][value=?][checked=checked]", action
    end
  end
end
