module Masks
  module Server
    require "test_helper"
    require_relative "../support/dpop"

    class TokenExchangeTest < ActionDispatch::IntegrationTest
      include DpopProofs

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

      test "a granted exchange is recorded with what it granted and never the token" do
        exchange(scope: "openid", resource: RESOURCES.first)

        event = within { Event.includes(:client).where(action: Event::EXCHANGE_GRANTED).sole }

        assert_equal @actor.id, event.actor_id
        assert_equal @registration["client_id"], event.client.client_id
        assert_equal "openid", event.details["scopes"]
        assert_equal [ RESOURCES.first ], event.details["audience"]
        assert_equal 1, event.details["depth"]
        refute_includes event.details.to_json, @subject
      end

      test "a refused exchange is recorded with the error it answered" do
        exchange(scope: "openid profile email admin")

        event = within { Event.where(action: Event::EXCHANGE_REFUSED).sole }

        assert_equal "invalid_scope", event.details["error"]
        assert_equal @actor.id, event.actor_id
        refute within { Event.where(action: Event::EXCHANGE_GRANTED).exists? }
      end

      test "an unreadable subject token is recorded as refused without an account" do
        exchange("not.a.jwt")

        event = within { Event.where(action: Event::EXCHANGE_REFUSED).sole }

        assert_equal "invalid_grant", event.details["error"]
        assert_nil event.actor_id
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

      test "a public client cannot turn an id token into an access token" do
        public = register(client_name: "Public", token_endpoint_auth_method: "none",
                          grant_types: [ "authorization_code", "refresh_token", EXCHANGE ])
        granted = access_token_for(actor: @actor, registration: public)

        assert granted["id_token"].present?

        body = exchange(granted["id_token"], registration: public, subject_token_type: Exchange::ID_TOKEN, scope: "openid")

        assert_equal "unauthorized_client", body["error"]
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

      test "a token held to a key is not exchanged without a proof made with that key" do
        bound = bound_subject
        thief = register(client_name: "Thief", token_endpoint_auth_method: "none", grant_types: [ EXCHANGE ])

        body = token(grant_type: EXCHANGE, subject_token: bound, subject_token_type: Exchange::ACCESS_TOKEN,
                     client_id: thief["client_id"])

        assert_equal "invalid_dpop_proof", body["error"]
        assert_match "subject_token", body["error_description"]

        stranger = OpenSSL::PKey::EC.generate("prime256v1")
        body = exchange_with(bound, with_dpop(method: :post, url: "#{origin_for(@tenant)}/token", key: stranger))

        assert_equal "invalid_dpop_proof", body["error"]
      end

      test "a token held to a key is exchanged with a proof made with it, and the new token is held to it too" do
        body = exchange_with(bound_subject, with_dpop(method: :post, url: "#{origin_for(@tenant)}/token"))

        assert_equal "DPoP", body["token_type"]
        assert_equal dpop_jkt, claims_in(body["access_token"]).dig("cnf", "jkt")
      end

      test "an exchange never leaves a client holding a scope it is not allowed" do
        narrow = register(client_name: "Narrow", scope: "openid", grant_types: [ "authorization_code", EXCHANGE ])

        assert_equal "openid", exchange(registration: narrow)["scope"]

        body = exchange(registration: narrow, scope: "openid email")

        assert_equal "invalid_scope", body["error"]
        assert_match "email", body["error_description"]
      end

      private

        def bound_subject
          reset!
          host! host_for(@tenant)
          code = authorized_code(actor: @actor, registration: @registration, resource: RESOURCES)

          post "/token",
               params: URI.encode_www_form(
                 grant_type: "authorization_code", code: code, redirect_uri: OidcFlow::REDIRECT_URI,
                 code_verifier: verifier, client_id: @registration["client_id"],
                 client_secret: @registration["client_secret"]
               ),
               headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }
                 .merge(with_dpop(method: :post, url: "#{origin_for(@tenant)}/token"))

          JSON.parse(response.body).fetch("access_token")
        end

        def exchange_with(subject_token, headers)
          post "/token",
               params: URI.encode_www_form(
                 grant_type: EXCHANGE, subject_token: subject_token, subject_token_type: Exchange::ACCESS_TOKEN,
                 client_id: @registration["client_id"], client_secret: @registration["client_secret"]
               ),
               headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }.merge(headers)

          JSON.parse(response.body)
        end
    end
  end
end
