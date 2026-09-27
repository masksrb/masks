module Masks
  module Server
    require "test_helper"

    class IdleAccountsTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper

      setup do
        host! host_for(@tenant)

        @tenant.update!(suspend_after: 365)
        @idle = create_actor(@tenant, nickname: "idle", email: "idle@example.com", email_verified_at: Time.current)
        idle_for(400.days)

        ActionMailer::Base.deliveries.clear
      end

      def idle_for(span, actor = @idle)
        within { actor.update_columns(last_active_at: span.ago) }
      end

      def sweep
        perform_enqueued_jobs { IdleAccountsJob.perform_now }
        within { @idle.reload if Actor.exists?(@idle.id) }
      end

      def mailed
        ActionMailer::Base.deliveries.select { |sent| sent.to == [ "idle@example.com" ] }
      end

      test "an idle account is warned by email before it is suspended" do
        with_mailer { sweep }

        within do
          assert_not @idle.suspended?
          assert_equal IdleAccounts::SUSPEND, @idle.idle_warning
          assert Event.exists?(action: Event::ACTOR_IDLE_WARNED, actor_id: @idle.id)
        end

        mail = mailed.sole

        assert_includes mail.subject, "Sign in to keep your Demo account"
        assert_includes mail.text_part.body.to_s, "it will be suspended"
      end

      test "a warned account is suspended once thirty days have passed" do
        sweep

        travel 29.days do
          sweep
          within { assert_not @idle.suspended? }
        end

        travel 31.days do
          sweep

          within do
            assert @idle.suspended?
            assert @idle.idle_suspended?
            event = Event.where(action: Event::ACTOR_SUSPENDED, actor_id: @idle.id).sole
            assert_nil event.by_id
            assert_equal "idle", event.details["reason"]
          end
        end
      end

      test "turning the setting on gives an account that went idle long ago its thirty days" do
        idle_for(5.years)

        sweep

        within { assert_not @idle.suspended? }
      end

      test "a suspended idle account is warned again, then deleted" do
        @tenant.update!(delete_after: 730)
        within { Session.start!(actor: @idle) }
        idle_for(800.days)

        with_mailer do
          sweep
          travel(31.days) { sweep }

          within { assert @idle.suspended? }

          travel 32.days do
            sweep

            within { assert_equal IdleAccounts::DELETE, @idle.idle_warning }

            warning = mailed.last
            assert_includes warning.subject, "will be deleted"
            assert_includes warning.text_part.body.to_s, "unless a manager restores it"
            assert_not_includes warning.text_part.body.to_s, "Signing in once keeps it"
          end

          travel 63.days do
            sweep

            within do
              assert_not Actor.exists?(@idle.id)
              assert_empty Session.where(actor_id: @idle.id).to_a
              assert Event.exists?(action: Event::ACTOR_DELETED, by_id: nil)
            end
          end
        end
      end

      test "a tenant that only deletes warns and deletes an active account" do
        @tenant.update!(suspend_after: nil, delete_after: 365)

        with_mailer { sweep }
        assert_includes mailed.last.text_part.body.to_s, "it will be deleted"

        travel 31.days do
          sweep
          within { assert_not Actor.exists?(@idle.id) }
        end
      end

      test "an account a manager suspended is never deleted for being idle" do
        @tenant.update!(suspend_after: nil, delete_after: 365)
        within { @idle.suspend! }
        idle_for(900.days)

        sweep
        travel(31.days) { sweep }

        within do
          assert Actor.exists?(@idle.id)
          assert_nil @idle.idle_warned_at
        end
      end

      test "deleting has to come after suspending" do
        @tenant.suspend_after = 365
        @tenant.delete_after = 365

        assert_not @tenant.valid?
        assert_includes @tenant.errors[:delete_after], "must be longer than suspend after"
      end

      test "signing in after the warning keeps the account" do
        sweep

        travel 10.days do
          sign_in_as(@idle)
        end

        travel 31.days do
          sweep

          within do
            assert_not @idle.suspended?
            assert_nil @idle.idle_warned_at
          end
        end
      end

      test "an app refreshing its token counts as the person using the account" do
        registration = register
        issued = access_token_for(actor: @idle, registration: registration)

        within { @idle.update_columns(last_active_at: 400.days.ago, idle_warned_at: 1.day.ago, idle_warning: "suspend") }

        token(
          grant_type: "refresh_token", refresh_token: issued["refresh_token"],
          client_id: registration["client_id"], client_secret: registration["client_secret"]
        )

        within do
          @idle.reload
          assert_operator @idle.last_active_at, :>, 1.minute.ago
          assert_nil @idle.idle_warned_at
        end
      end

      test "the last manager and a provisioned account are left alone" do
        manager = create_actor(@tenant, nickname: "boss", scopes: "openid masks:manage")
        provisioned = create_actor(@tenant, nickname: "scim", external_id: "okta-1")

        within do
          Actor.where(id: [ manager.id, provisioned.id ]).update_all(last_active_at: 400.days.ago)
        end

        sweep

        travel 31.days do
          sweep

          within do
            assert_nil manager.reload.idle_warned_at
            assert_not manager.suspended?
            assert_nil provisioned.reload.idle_warned_at
            assert @idle.suspended?
          end
        end
      end

      test "changing the setting gives every warned account a fresh thirty days" do
        sweep

        travel 31.days do
          @tenant.update!(suspend_after: 730)
          @tenant.update!(suspend_after: 365)
          sweep

          within do
            assert_not @idle.suspended?
            assert_operator @idle.idle_warned_at, :>, 1.minute.ago
          end
        end
      end

      test "a tenant with the setting off sweeps nothing" do
        @tenant.update!(suspend_after: nil)

        sweep

        within { assert_nil @idle.idle_warned_at }
      end

      test "restoring a suspended account starts its idle clock again" do
        sweep

        travel 31.days do
          sweep
          within { @idle.restore! }
          sweep

          within do
            assert_not @idle.suspended?
            assert_not @idle.idle_suspended?
            assert_nil @idle.idle_warned_at
          end
        end
      end
    end
  end
end
