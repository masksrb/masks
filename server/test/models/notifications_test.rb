require "test_helper"

class NotificationsTest < ActiveSupport::TestCase
  setup do
    @actor = create_actor(@tenant, email: "owner@example.com", email_verified_at: Time.current)
  end

  def with_mailer(from: "masks@example.com")
    held = Rails.configuration.masks.mail_from
    Rails.configuration.masks.mail_from = from
    yield
  ensure
    Rails.configuration.masks.mail_from = held
  end

  test "every mailable action is one the audit log actually records" do
    Notifications::MAILED.each do |action|
      assert_includes Event::ACTIONS, action, "#{action} is offered but never recorded"
    end
  end

  test "every mailable action has a sentence to say and a label to check" do
    Notifications::MAILED.each do |action|
      assert I18n.exists?("actor_mailer.notification.said.#{action}"),
             "#{action} has no sentence in the email"
      assert I18n.exists?("events.actions.#{action}"),
             "#{action} has no label on the account page"
    end
  end

  test "every group is named and no action is offered twice" do
    Notifications::GROUPS.each_key do |group|
      assert I18n.exists?("notifications.groups.#{group}"), "#{group} has no heading"
    end

    assert_equal Notifications::MAILED.length, Notifications::MAILED.uniq.length
  end

  test "a new account hears about everything" do
    assert_equal Notifications::MAILED, @actor.notifications
    Notifications::MAILED.each { |action| assert @actor.notified?(action) }
  end

  test "what is left out of the form is what gets muted" do
    within(@tenant) do
      @actor.update!(notifications: [ Event::PASSWORD_CHANGED ])

      assert @actor.notified?(Event::PASSWORD_CHANGED)
      refute @actor.notified?(Event::PASSKEY_ADDED)
      assert_equal [ Event::PASSWORD_CHANGED ], @actor.notifications
    end
  end

  test "an action masks does not mail is never notified, muted or not" do
    refute @actor.notified?(Event::AVATAR_UPLOADED)
    refute @actor.notified?("nonsense")
  end

  test "nothing is sent to an address nobody has confirmed" do
    with_mailer do
      within(@tenant) do
        refute Notifications.mailable?(create_actor(@tenant, nickname: "unconfirmed", email: "u@example.com"))
        refute Notifications.mailable?(create_actor(@tenant, nickname: "addressless"))
        assert Notifications.mailable?(@actor)
      end
    end
  end

  test "with no mailer configured nothing is sent at all" do
    refute Notifications.mailable?(@actor)
  end

  test "a device that has signed in before is not announced twice" do
    within(@tenant) do
      device = Device.identify(nil)
      first = Event.record!(Event::SESSION_STARTED, actor: @actor, device: device)
      again = Event.record!(Event::SESSION_STARTED, actor: @actor, device: device)
      elsewhere = Event.record!(Event::SESSION_STARTED, actor: @actor, device: Device.identify(nil))

      assert Notifications.worth_saying?(first)
      refute Notifications.worth_saying?(again)
      assert Notifications.worth_saying?(elsewhere)
    end
  end

  test "an event with nothing to do with email raises no job" do
    within(@tenant) do
      refute Notifications.raised(Event.record!(Event::AVATAR_UPLOADED, actor: @actor))
    end
  end
end
