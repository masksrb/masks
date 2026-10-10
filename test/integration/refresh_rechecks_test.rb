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
    end
  end
end
