module Masks
  module Server
    require "test_helper"

    class NotificationEmailTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper

      setup do
        host! host_for(@tenant)

        @actor = create_actor(@tenant, email: "owner@example.com", email_verified_at: Time.current)
      end

      def delivered
        perform_enqueued_jobs { yield }

        ActionMailer::Base.deliveries
      end

      def change_password!
        patch "/account/password", params: { current_password: "password", password: "hunter2hunter2" }
      end

      def add_passkey!
        within(@tenant) { Event.record!(Event::PASSKEY_ADDED, actor: @actor, passkey: "laptop") }
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
                params: { notifications: Notifications::MUTABLE - [ Event::PASSKEY_ADDED ] }

          assert_redirected_to "#{root_path}#notifications"
          ActionMailer::Base.deliveries.clear

          subjects = delivered { add_passkey! }.map(&:subject)

          refute subjects.any? { |subject| subject.include?("Passkey added") }
        end
      end

      test "the form cannot mute an action masks does not offer" do
        with_mailer do
          sign_in_as(@actor)

          patch "/account/notifications", params: { notifications: [ "", "avatar.uploaded", "../../etc" ] }

          within(@tenant) { assert_equal Notifications::MUTABLE.sort, @actor.reload.muted_notifications.sort }
        end
      end

      test "a changed password is announced even when everything is turned off" do
        with_mailer do
          sign_in_as(@actor)

          patch "/account/notifications", params: { notifications: [] }
          ActionMailer::Base.deliveries.clear

          subjects = delivered { change_password! }.map(&:subject)

          assert subjects.any? { |subject| subject.include?("Password changed") }
          within(@tenant) { refute_includes @actor.reload.muted_notifications, Event::PASSWORD_CHANGED }
        end
      end

      test "the form says which emails are always sent" do
        sign_in_as(@actor)
        get "/"

        assert_select "#notify-password-changed", count: 0
        assert_select "#notify-session-started", count: 1
        assert_includes response.body, "always announced"
      end

      test "changing which emails arrive is recorded as activity" do
        sign_in_as(@actor)

        patch "/account/notifications", params: { notifications: Notifications::MUTABLE - [ Event::SESSION_STARTED ] }

        event = within(@tenant) { Event.where(action: Event::NOTIFICATIONS_CHANGED, actor: @actor).last }

        assert event
        assert_equal [ Event::SESSION_STARTED ], event.details["muted"]
        assert_empty event.details["unmuted"]

        patch "/account/notifications", params: { notifications: Notifications::MUTABLE }

        event = within(@tenant) { Event.where(action: Event::NOTIFICATIONS_CHANGED, actor: @actor).last }

        assert_equal [ Event::SESSION_STARTED ], event.details["unmuted"]

        patch "/account/notifications", params: { notifications: Notifications::MUTABLE }

        assert_equal 2, within(@tenant) { Event.where(action: Event::NOTIFICATIONS_CHANGED, actor: @actor).count }
      end

      test "turning emails off asks for a recent sign-in" do
        sign_in_as(@actor)

        travel 16.minutes do
          patch "/account/notifications", params: { notifications: [] }

          assert_redirected_to %r{/login}
          within(@tenant) { assert_empty @actor.reload.muted_notifications }
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

        Notifications::MUTABLE.each do |action|
          assert_select "input[type=checkbox][value=?][checked=checked]", action
        end

        Notifications::ALWAYS.each do |action|
          assert_select "input[type=checkbox][value=?]", action, count: 0
        end
      end
    end
  end
end
