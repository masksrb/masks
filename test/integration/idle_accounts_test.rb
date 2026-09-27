module Masks
  module Server
    require "test_helper"

    class IdleAccountsTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper

      setup do
        host! host_for(@tenant)

        @tenant.update!(idle_after: 365)
        @idle = create_actor(@tenant, nickname: "idle", email: "idle@example.com", email_verified_at: Time.current)
        within { @idle.update_columns(last_active_at: 400.days.ago) }

        ActionMailer::Base.deliveries.clear
      end

      def sweep
        perform_enqueued_jobs { IdleAccountsJob.perform_now }
        within { @idle.reload if Actor.exists?(@idle.id) }
      end

      test "an idle account is warned by email before anything happens to it" do
        with_mailer { sweep }

        within do
          assert_not @idle.suspended?
          assert @idle.idle_warned_at.present?
          assert Event.exists?(action: Event::ACTOR_IDLE_WARNED, actor_id: @idle.id)
        end

        mail = ActionMailer::Base.deliveries.find { |sent| sent.to == [ "idle@example.com" ] }

        assert mail, "no warning was mailed"
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
            event = Event.where(action: Event::ACTOR_SUSPENDED, actor_id: @idle.id).sole
            assert_nil event.by_id
            assert_equal "idle", event.details["reason"]
          end
        end
      end

      test "turning the setting on gives an account that went idle long ago its thirty days" do
        within { @idle.update_columns(last_active_at: 5.years.ago) }

        sweep

        within { assert_not @idle.suspended? }
      end

      test "a tenant set to delete deletes the account and signs it out everywhere" do
        @tenant.update!(idle_action: Tenant::IDLE_DELETE)
        within { Session.start!(actor: @idle) }

        with_mailer { sweep }
        assert_includes ActionMailer::Base.deliveries.last.text_part.body.to_s, "it will be deleted"

        travel 31.days do
          sweep

          within do
            assert_not Actor.exists?(@idle.id)
            assert_empty Session.where(actor_id: @idle.id).to_a
            assert Event.exists?(action: Event::ACTOR_DELETED, by_id: nil)
          end
        end
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

        within { @idle.update_columns(last_active_at: 400.days.ago, idle_warned_at: 1.day.ago) }

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

      test "a tenant with the setting off sweeps nothing" do
        @tenant.update!(idle_after: nil)

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
            assert_nil @idle.idle_warned_at
          end
        end
      end
    end
  end
end
