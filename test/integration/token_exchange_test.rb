module Masks
  module Server
    require "test_helper"

    class TokenExchangeTest < ActionDispatch::IntegrationTest
      EXCHANGE = Exchange::GRANT_TYPE
      RESOURCES = [ "https://probe.example.com/mcp", "https://probe.example.com/files" ].freeze

      setup do
        @actor = create_actor(email: "owner@probe.example.com", name: "Owner")
        @registration = register(grant_types: [ "authorization_code", "refresh_token", EXCHANGE ])
        host! host_for(@tenant)

        @granted = access_token_for(actor: @actor, registration: @registration, resource: RESOURCES)
        @subject = @granted["access_token"]
      end

      def exchange(subject_token = @subject, registration: @registration, **params)
        token(
          grant_type: EXCHANGE,
          subject_token: subject_token,
          subject_token_type: Exchange::ACCESS_TOKEN,
          client_id: registration["client_id"],
          client_secret: registration["client_secret"],
          **params
        )
      end

      test "an exchange narrows scope, audience and lifetime at once" do
        body = exchange(scope: "openid", resource: RESOURCES.first, requested_lifetime: 60)

        assert_equal Exchange::ACCESS_TOKEN, body["issued_token_type"]
        assert_equal "openid", body["scope"]
        assert_operator body["expires_in"], :<=, 60

        claims = claims_in(body["access_token"])
        assert_equal RESOURCES.first, claims["aud"]
        assert_equal @actor.uuid, claims["sub"]
      end

      test "an exchange cannot widen scope" do
        body = exchange(scope: "openid profile email admin")

        assert_equal "invalid_scope", body["error"]
        assert_match "admin", body["error_description"]
      end

      test "an exchange cannot widen audience" do
        body = exchange(resource: "https://elsewhere.example.com/mcp")

        assert_equal "invalid_target", body["error"]
        assert_match "elsewhere", body["error_description"]
      end

      test "the subject token's expiry is the ceiling however long a lifetime is asked for" do
        body = exchange(requested_lifetime: 10.days.to_i)

        assert_operator body["expires_in"], :<=, AccessToken.lifetime.to_i
      end

      test "an exchange inherits scope and audience when it asks for neither" do
        claims = claims_in(exchange["access_token"])

        assert_equal RESOURCES.sort, Array(claims["aud"]).sort
        assert_equal "email offline_access openid profile", claims["scope"]
      end

      test "an exchanged token names the client that exchanged it" do
        downstream = register(client_name: "Downstream",
                              grant_types: [ "authorization_code", EXCHANGE ])

        claims = claims_in(exchange(registration: downstream)["access_token"])

        assert_equal downstream["client_id"], claims.dig("act", "sub")
      end

      test "the act claim nests on each further exchange" do
        first = register(client_name: "First", grant_types: [ "authorization_code", EXCHANGE ])
        second = register(client_name: "Second", grant_types: [ "authorization_code", EXCHANGE ])

        once = exchange(registration: first)["access_token"]
        twice = exchange(once, registration: second)["access_token"]

        claims = claims_in(twice)
        assert_equal second["client_id"], claims.dig("act", "sub")
        assert_equal first["client_id"], claims.dig("act", "act", "sub")
      end

      test "a client not registered for the exchange grant cannot exchange" do
        plain = register(client_name: "Plain", grant_types: [ "authorization_code" ])

        assert_equal "unauthorized_client", exchange(registration: plain)["error"]
      end

      test "an unverifiable subject token is refused" do
        assert_equal "invalid_grant", exchange("not.a.jwt")["error"]
      end

      test "a token signed for another tenant is not exchangeable here" do
        stranger = create_actor(other_tenant, nickname: "stranger")
        elsewhere = register(other_tenant, grant_types: [ "authorization_code", EXCHANGE ])

        host! host_for(other_tenant)
        foreign = access_token_for(actor: stranger, registration: elsewhere)["access_token"]

        host! host_for(@tenant)
        assert_equal "invalid_grant", exchange(foreign)["error"]
      end

      test "an unsupported token type is refused" do
        body = exchange(subject_token_type: "urn:ietf:params:oauth:token-type:saml2")

        assert_equal "invalid_request", body["error"]
      end

      test "a client exchanges the id token it was issued for an access token within what the person consented to" do
        body = exchange(@granted["id_token"], subject_token_type: Exchange::ID_TOKEN, scope: "openid profile",
                                             resource: RESOURCES.first)

        assert_equal "openid profile", body["scope"], body
        claims = claims_in(body["access_token"])

        assert_equal @actor.uuid, claims["sub"]
        assert_equal RESOURCES.first, claims["aud"]
        assert_nil claims["act"]
        assert_operator body["expires_in"], :<=, 15.minutes.to_i
      end

      test "an id token cannot be exchanged for more than the person consented to" do
        body = exchange(@granted["id_token"], subject_token_type: Exchange::ID_TOKEN, scope: "openid admin")

        assert_equal "invalid_scope", body["error"]
      end

      test "another client cannot exchange somebody else's id token" do
        thief = register(client_name: "Thief", grant_types: [ "authorization_code", EXCHANGE ])

        body = exchange(@granted["id_token"], registration: thief, subject_token_type: Exchange::ID_TOKEN, scope: "openid")

        assert_equal "invalid_grant", body["error"]
      end

      test "an id token from a session that has ended is not exchangeable" do
        within { Session.where(actor: @actor).find_each(&:revoke!) }

        body = exchange(@granted["id_token"], subject_token_type: Exchange::ID_TOKEN, scope: "openid")

        assert_equal "invalid_grant", body["error"]
      end

      test "an access token cannot pass as an id token" do
        body = exchange(@subject, subject_token_type: Exchange::ID_TOKEN)

        assert_equal "invalid_grant", body["error"]
      end

      test "an actor token names who is acting in the act claim" do
        within do
          Client.find_by!(client_id: @registration["client_id"]).update!(
            grant_types: [ "authorization_code", "refresh_token", EXCHANGE, Client::CLIENT_CREDENTIALS ],
            approved_at: Time.current, allowed_scopes: "openid profile email offline_access agent:run"
          )
        end

        own = token(grant_type: Client::CLIENT_CREDENTIALS, client_id: @registration["client_id"],
                    client_secret: @registration["client_secret"])["access_token"]

        body = exchange(actor_token: own, actor_token_type: Exchange::ACCESS_TOKEN, scope: "openid")
        claims = claims_in(body["access_token"])

        assert_equal @actor.uuid, claims["sub"], body
        assert_equal @registration["client_id"], claims.dig("act", "sub")
        assert_equal @registration["client_id"], claims.dig("act", "client_id")
      end

      test "an actor token issued to another client is refused" do
        other = register(client_name: "Other", grant_types: [ "authorization_code", EXCHANGE ])
        theirs = access_token_for(actor: create_actor(nickname: "else", email: "else@probe.example.com"), registration: other)["access_token"]

        body = exchange(actor_token: theirs, actor_token_type: Exchange::ACCESS_TOKEN)

        assert_equal "invalid_grant", body["error"]
        assert_match "actor_token", body["error_description"]
      end

      test "an actor token without its type is refused" do
        assert_equal "invalid_request", exchange(actor_token: @subject)["error"]
      end
    end
  end
end
