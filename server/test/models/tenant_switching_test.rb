require "test_helper"

class TenantSwitchingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @mail_from = Rails.configuration.masks.mail_from
    Rails.configuration.masks.mail_from = "masks@example.invalid"

    ActionMailer::Base.deliveries.clear
  end

  teardown { Rails.configuration.masks.mail_from = @mail_from }

  def statements
    collected = []

    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      collected << payload[:sql]
    end

    yield

    collected
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test "switching to the tenant already current costs nothing" do
    within(@tenant) do
      sql = statements { within(@tenant) { Current.tenant } }

      assert_empty sql, "a re-entrant switch must not touch the database"
    end
  end

  test "a re-entrant switch opens no savepoint of its own" do
    within(@tenant) do
      depth = ActiveRecord::Base.connection.open_transactions

      within(@tenant) do
        assert_equal depth, ActiveRecord::Base.connection.open_transactions
      end
    end
  end

  test "a re-entrant switch still isolates, and still restores a real one" do
    create_actor(@tenant, nickname: "owner")

    within(@tenant) do
      within(@tenant) { assert_equal 1, Actor.count }
      within(@other) { assert_equal 0, Actor.count }

      assert_equal 1, Actor.count
    end
  end

  test "a job carries the tenant it was enqueued in" do
    actor = create_actor(@tenant, nickname: "invitee", email: "invitee@example.invalid")

    within(@tenant) do
      ActorMailer.email_verification(
        actor, "http://auth.example.test/verify/token", tenant_name: @tenant.name
      ).deliver_later
    end

    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      perform_enqueued_jobs
    end

    assert_equal [ "invitee@example.invalid" ], ActionMailer::Base.deliveries.last.to
  end

  test "a job enqueued in one tenant does not perform in whichever ran last" do
    mine = create_actor(@tenant, nickname: "mine", email: "mine@example.invalid")
    theirs = create_actor(@other, nickname: "theirs", email: "theirs@example.invalid")

    within(@tenant) do
      ActorMailer.email_verification(mine, "http://auth.example.test/a", tenant_name: @tenant.name).deliver_later
    end

    within(@other) do
      ActorMailer.email_verification(theirs, "http://auth.example.test/b", tenant_name: @other.name).deliver_later
    end

    perform_enqueued_jobs

    assert_equal [ "mine@example.invalid", "theirs@example.invalid" ],
                 ActionMailer::Base.deliveries.map { |mail| mail.to.sole }.sort
  end

  test "a job whose tenant is gone fails rather than performing outside one" do
    actor = create_actor(@tenant, nickname: "invitee", email: "invitee@example.invalid")

    within(@tenant) do
      ActorMailer.email_verification(actor, "http://auth.example.test/a", tenant_name: @tenant.name).deliver_later
    end

    Tenant.switch(@tenant) { @tenant.update!(archived_at: Time.current) }

    assert_raises(ActiveRecord::RecordNotFound) { perform_enqueued_jobs }
  end

  test "a job enqueued outside a tenant performs outside one" do
    assert_nothing_raised { CleanupJob.perform_later }
    assert_nothing_raised { perform_enqueued_jobs }
  end
end
