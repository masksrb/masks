module Masks
  module Server
    require "test_helper"

    class GroupsTest < ActionDispatch::IntegrationTest
      setup do
        @actor = create_actor(email: "ada@example.com")
        @registration = approve!(register(scope: "openid profile email offline_access groups"))
        host! host_for(@tenant)

        @family = within { Group.create!(key: "family", name: "Family") }
      end

      def client
        within { Client.find_by(client_id: @registration["client_id"]) }
      end

      def admitted(*groups)
        within { client.update!(allowed_groups: groups) }
      end

      def granted(scope)
        code = authorized_code(actor: @actor, registration: @registration, scope: scope)

        token(grant_type: "authorization_code", code: code, redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier,
              client_id: @registration["client_id"], client_secret: @registration["client_secret"])
      end

      def refresh(value)
        token(grant_type: "refresh_token", refresh_token: value,
              client_id: @registration["client_id"], client_secret: @registration["client_secret"])
      end

      test "the groups claim lists each group and each organization role" do
        within do
          @family.add!(@actor)
          acme = Organization.create!(key: "acme", name: "Acme")
          acme.memberships.create!(actor: @actor, role: "owner")
        end

        granted = granted("openid profile groups offline_access")

        assert_equal %w[acme:owner family], claims_in(granted["id_token"])["groups"]

        get "/userinfo", headers: { "HTTP_AUTHORIZATION" => "Bearer #{granted['access_token']}" }

        assert_equal %w[acme:owner family], JSON.parse(response.body)["groups"]
      end

      test "a person with an explicit scope list still gets the groups claim" do
        within do
          @actor.update!(scopes: "openid profile email offline_access")
          @family.add!(@actor)
        end

        granted = granted("openid groups")

        assert_equal %w[family], claims_in(granted["id_token"])["groups"]
      end

      test "an app limited to a group turns away someone outside it" do
        admitted("family")

        sign_in_as(@actor)
        authorize(client_id: @registration["client_id"])
        consent! if awaiting_consent?

        assert_equal "access_denied", redirected["error"]
        assert within { Event.where(action: Event::LOGIN_REFUSED, actor: @actor).exists? }
      end

      test "an app limited to a group lets its members in" do
        admitted("family")
        within { @family.add!(@actor) }

        assert access_token_for(actor: @actor, registration: @registration)["access_token"].present?
      end

      test "an organization role can stand for a group" do
        admitted("acme:owner")
        within do
          acme = Organization.create!(key: "acme", name: "Acme")
          acme.memberships.create!(actor: @actor, role: "owner")
        end

        assert access_token_for(actor: @actor, registration: @registration)["access_token"].present?
      end

      test "someone taken out of the group cannot refresh" do
        admitted("family")
        within { @family.add!(@actor) }
        issued = access_token_for(actor: @actor, registration: @registration)

        within { @family.remove!(@actor) }

        assert_equal "invalid_grant", refresh(issued["refresh_token"])["error"]
      end

      test "an allowed group must look like a group key or an organization role" do
        assert_raises(ActiveRecord::RecordInvalid) { admitted("Not A Group!") }
      end

      def manage_token(actor, scope: "openid masks:manage")
        console = create_client(@tenant, allowed_scopes: "openid profile email masks:manage masks:manage:support",
                                         approved_at: Time.current, grant_types: [ "authorization_code" ])

        reset!
        host! host_for(@tenant)
        sign_in_as(actor)
        authorize(client_id: console.client_id, scope: scope, resource: issuer_for(@tenant).manage_resource)
        consent! if awaiting_consent?

        token(grant_type: "authorization_code", code: code_from, redirect_uri: OidcFlow::REDIRECT_URI,
              code_verifier: verifier, client_id: console.client_id)["access_token"]
      end

      def ask(query, bearer, **variables)
        manage(query, bearer: bearer, **variables)
      end

      test "an owner makes a group, puts someone in it, and limits an app to it" do
        owner = create_actor(@tenant, nickname: "boss", scopes: "openid profile email masks:manage")
        bearer = manage_token(owner)

        made = ask('mutation { createGroup(key: "kids", name: "Kids") { group { key } } }', bearer)
        assert_nil made["errors"]

        added = ask('mutation Add($uuid: ID!) { addGroupMember(key: "kids", uuid: $uuid) { group { memberCount } } }',
                    bearer, uuid: @actor.uuid)
        assert_equal 1, added.dig("data", "addGroupMember", "group", "memberCount")

        limited = ask('mutation Limit($id: ID!) { updateClient(clientId: $id, allowedGroups: ["kids"]) { client { allowedGroups } } }',
                      bearer, id: @registration["client_id"])
        assert_equal %w[kids], limited.dig("data", "updateClient", "client", "allowedGroups")

        held = ask("query Held($uuid: ID!) { actor(uuid: $uuid) { groupLabels } }", bearer, uuid: @actor.uuid)
        assert_equal %w[kids], held.dig("data", "actor", "groupLabels")
      end

      test "a support manager cannot change groups, since a group can let someone into an app" do
        helper = create_actor(@tenant, nickname: "helper", scopes: "openid profile email masks:manage:support")

        answer = ask('mutation { createGroup(key: "admins", name: "Admins") { group { key } } }',
                     manage_token(helper, scope: "openid masks:manage:support"))

        assert_match "security", answer["errors"].to_s
        refute within { Group.exists?(key: "admins") }
      end

      test "an owner adds Grafana from its preset and gets the settings to paste into it" do
        owner = create_actor(@tenant, nickname: "boss", scopes: "openid profile email masks:manage")
        bearer = manage_token(owner)

        added = ask(<<~GQL, bearer)
          mutation { addApp(preset: "grafana", baseUrl: "https://grafana.example.com/") {
            client { clientId name redirectUris allowedScopes clientUri } secret settings { label value } } }
        GQL

        assert_nil added["errors"]
        app = added.dig("data", "addApp")
        assert_equal [ "https://grafana.example.com/login/generic_oauth" ], app.dig("client", "redirectUris")
        assert_includes app.dig("client", "allowedScopes"), "groups"
        assert_equal "https://grafana.example.com", app.dig("client", "clientUri")

        held = app["settings"].to_h { |setting| [ setting["label"], setting["value"] ] }
        assert_equal app.dig("client", "clientId"), held["client_id"]
        assert_equal app["secret"], held["client_secret"]
      end

      test "an owner puts an app behind their proxy and gets the proxy's settings" do
        owner = create_actor(@tenant, nickname: "boss", scopes: "openid profile email masks:manage")

        added = ask(<<~GQL, manage_token(owner))
          mutation { addApp(preset: "proxy", baseUrl: "https://dash.example.com") {
            client { clientId name redirectUris } secret settings { label value } } }
        GQL

        assert_nil added["errors"]
        app = added.dig("data", "addApp")
        assert_equal "dash.example.com", app.dig("client", "name")
        assert_equal [ "https://dash.example.com/masks-auth/callback" ], app.dig("client", "redirectUris")
        assert_nil app["secret"]

        held = app["settings"].to_h { |setting| [ setting["label"], setting["value"] ] }
        assert_match "#{issuer_for(@tenant).url}/forward-auth", held["Traefik"]
        assert_match "header_up Host #{host_for(@tenant)}", held["Caddy"]
        assert within { Client.forwarding_to(URI("https://dash.example.com/x")) }
      end
    end
  end
end
