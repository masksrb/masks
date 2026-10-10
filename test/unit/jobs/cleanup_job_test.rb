module Masks
  module Server
    require "test_helper"

    class CleanupJobTest < ActiveSupport::TestCase
      setup do
        @actor = create_actor
        @client = create_client
      end

      def chain(refreshes:)
        within do
          session = Session.start!(actor: @actor)
          code = AuthorizationCode.mint!(actor: @actor, client: @client, session: session, scopes: "openid")
          code.consume!
          held = RefreshToken.mint!(actor: @actor, client: @client, parent: code, scopes: "openid")

          refreshes.times do
            held.consume!
            held = RefreshToken.mint!(actor: @actor, client: @client, parent: held, scopes: "openid")
          end

          [ code, held ]
        end
      end

      test "a code whose refresh token is still live is kept, and the job finishes" do
        code, live = chain(refreshes: 2)

        travel 8.days do
          within { live.update!(expires_at: 30.days.from_now) }

          CleanupJob.perform_now

          assert within { Token.exists?(code.id) }
          assert within { RefreshToken.redeem(live.secret) }
        end
      end

      test "a chain with nothing live left is deleted whole" do
        code, last = chain(refreshes: 3)

        travel RefreshToken.lifetime + CleanupJob::GRACE + 1.day do
          CleanupJob.perform_now

          refute within { Token.families(code.id).exists? }
          refute within { Token.exists?(last.id) }
        end
      end

      test "a spent refresh token stays recognizable while its chain is live" do
        _, live = chain(refreshes: 1)
        spent = within { live.parent }

        travel 20.days do
          CleanupJob.perform_now

          assert within { Token.exists?(spent.id) }
          assert_equal 1, within { spent.revoke_family! }
          refute within { RefreshToken.redeem(live.secret) }
        end
      end

      test "a session that ended stays while a live token names it" do
        _, live = chain(refreshes: 0)
        session = within { live.session }

        within { session.update!(expires_at: 1.minute.from_now) }

        travel 8.days do
          within { live.update!(expires_at: 30.days.from_now) }

          CleanupJob.perform_now

          assert within { Session.exists?(session.id) }
        end
      end

      test "one tenant failing does not stop the others" do
        other = other_tenant
        stale = within(other) { Session.start!(actor: create_actor(other)).tap { |held| held.update!(expires_at: 1.minute.from_now) } }

        failing = CleanupJob.new
        failing.define_singleton_method(:sweep) do |tenant|
          raise "broken" if tenant.id != other.id

          super(tenant)
        end

        travel 8.days do
          assert_raises(CleanupJob::Incomplete) { failing.perform_now }

          refute within(other) { Session.exists?(stale.id) }
        end
      end
    end
  end
end
