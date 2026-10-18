module Masks
  module Server
    require "test_helper"

    class RefreshRechecksTest < ActionDispatch::IntegrationTest
      setup do
        @actor = create_actor(scopes: "openid profile email offline_access")
        @registration = register
        host! host_for(@tenant)
      end

      def refresh(value)
        token(
          grant_type: "refresh_token", refresh_token: value,
          client_id: @registration["client_id"], client_secret: @registration["client_secret"]
        )
      end

      def client
        within { Client.find_by(client_id: @registration["client_id"]) }
      end

      test "a scope taken from the person is gone from the next refresh" do
        issued = access_token_for(actor: @actor, registration: @registration)

        assert_includes Scopes.list(issued["scope"]), "email"

        within { @actor.update!(scopes: "openid offline_access") }
        rotated = refresh(issued["refresh_token"])

        assert rotated["access_token"].present?
        refute_includes Scopes.list(rotated["scope"]), "email"
        refute_includes Scopes.list(rotated["scope"]), "profile"
      end

      test "a scope taken from the client is gone from the next refresh" do
        issued = access_token_for(actor: @actor, registration: @registration)

        within { client.update!(allowed_scopes: "openid offline_access") }

        refute_includes Scopes.list(refresh(issued["refresh_token"])["scope"]), "email"
      end

      test "a lapsed consent ends the refresh token" do
        issued = access_token_for(actor: @actor, registration: @registration)

        within { Consent.find_by!(actor: @actor, client: client).update!(expires_at: 1.minute.ago) }

        assert_equal "invalid_grant", refresh(issued["refresh_token"])["error"]
      end

      test "a refresh within a live consent carries on" do
        issued = access_token_for(actor: @actor, registration: @registration)

        assert refresh(issued["refresh_token"])["access_token"].present?
      end

      test "a client's own lifetimes set how long its tokens last" do
        within { client.update!(access_token_lifetime: 300, refresh_token_lifetime: 2.days.to_i) }

        issued = access_token_for(actor: @actor, registration: @registration)

        assert_operator issued["expires_in"], :<=, 300
        assert_operator claims_in(issued["access_token"])["exp"], :<=, 5.minutes.from_now.to_i + 1

        travel 3.days do
          assert_equal "invalid_grant", refresh(issued["refresh_token"])["error"]
        end
      end

      test "a lifetime outside what masks allows is refused" do
        assert_raises(ActiveRecord::RecordInvalid) { within { client.update!(access_token_lifetime: 10) } }
        assert_raises(ActiveRecord::RecordInvalid) { within { client.update!(refresh_token_lifetime: 500.days.to_i) } }
        assert_raises(ActiveRecord::RecordInvalid) { within { client.update!(refresh_token_absolute_lifetime: 10) } }
      end

      test "a refresh chain stops at the client's limit however often it is used" do
        within { client.update!(refresh_token_lifetime: 1.day.to_i, refresh_token_absolute_lifetime: 2.days.to_i) }

        issued = access_token_for(actor: @actor, registration: @registration)
        travel 20.hours
        rotated = refresh(issued["refresh_token"])
        assert rotated["refresh_token"].present?
        travel 20.hours
        rotated = refresh(rotated["refresh_token"])
        assert rotated["refresh_token"].present?
        travel 20.hours

        assert_equal "invalid_grant", refresh(rotated["refresh_token"])["error"]
        assert_equal 0, within { AccessToken.live.where(client: client).count }
      end

      test "a refresh chain stops 90 days after the sign-in by default" do
        issued = access_token_for(actor: @actor, registration: @registration)
        held = issued["refresh_token"]

        3.times do
          travel 29.days
          held = refresh(held)["refresh_token"]
          assert held.present?
        end

        travel 29.days

        assert_equal "invalid_grant", refresh(held)["error"]
      end
    end
  end
end
