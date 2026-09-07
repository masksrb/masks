require "test_helper"

class ProbeJob < ApplicationJob
  cattr_accessor :performed_in

  def perform = self.class.performed_in = Current.tenant&.subdomain
end

class SweepJob < ApplicationJob
  across_tenants!

  cattr_accessor :performed_in

  def perform = self.class.performed_in = Current.tenant&.subdomain
end

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
      within(other_tenant) { assert_equal 0, Actor.count }

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
    theirs = create_actor(other_tenant, nickname: "theirs", email: "theirs@example.invalid")

    within(@tenant) do
      ActorMailer.email_verification(mine, "http://auth.example.test/a", tenant_name: @tenant.name).deliver_later
    end

    within(other_tenant) do
      ActorMailer.email_verification(theirs, "http://auth.example.test/b", tenant_name: other_tenant.name).deliver_later
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

  test "a job enqueued outside a tenant is refused rather than left to guess" do
    assert_raises(Tenancy::Job::Homeless) { ProbeJob.perform_later }
  end

  test "a job that declares itself across tenants may be enqueued outside one" do
    assert_nothing_raised { SweepJob.perform_later }

    perform_enqueued_jobs

    assert_nil SweepJob.performed_in
  end

  test "the recurring sweep is enqueued outside a tenant, as its schedule reaches it" do
    assert_nothing_raised { CleanupJob.perform_later }
    assert_nothing_raised { perform_enqueued_jobs }
  end

  test "every job the schedule reaches declares itself across tenants" do
    [ CleanupJob, RefreshAuthenticatorsJob ].each do |job|
      assert job.across_tenants, "#{job} is reached by the scheduler, which holds no tenant"
      assert_nothing_raised { job.perform_later }
    end
  end

  test "mail is carried by the framework's own delivery job, with no subclass to remember" do
    assert_equal ActionMailer::MailDeliveryJob, ActionMailer::Base.delivery_job
    assert ActionMailer::MailDeliveryJob < Tenancy::Job
  end

  test "a switch holds no transaction open" do
    depth = ActiveRecord::Base.connection.open_transactions

    within(other_tenant) do
      assert_equal depth, ActiveRecord::Base.connection.open_transactions,
                   "a request must not sit inside a transaction for its whole life, or an " \
                   "outbound call to a provider holds one open for its timeout"
    end
  end

  test "leaving a tenant leaves nothing behind on the connection" do
    create_actor(@tenant, nickname: "owner")

    within(@tenant) { assert_equal 1, Actor.count }

    assert_equal 0, Actor.unscoped.count,
                 "the setting outlived the switch, so the next request to pick up this " \
                 "connection would read the last one's rows"
  end

  test "a switch that raises leaves nothing behind either" do
    create_actor(@tenant, nickname: "owner")

    assert_raises(RuntimeError) { within(@tenant) { raise "boom" } }

    assert_equal 0, Actor.unscoped.count
  end
end
