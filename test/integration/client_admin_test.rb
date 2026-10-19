module Masks
  module Server
    require "test_helper"

    class ClientAdminTest < ActionDispatch::IntegrationTest
      setup do
        host! host_for(@tenant)

        @actor = create_actor(@tenant, scopes: "openid profile email masks:manage")
        @console = create_client(
          @tenant,
          name: "Console",
          allowed_scopes: "openid profile email masks:manage",
          approved_at: Time.current,
          grant_types: [ "authorization_code", "refresh_token" ]
        )
      end

      def resource
        @resource ||= issuer_for(@tenant).manage_resource
      end

      def bearer
        @bearer ||= begin
          sign_in_as(@actor)
          authorize(client_id: @console.client_id, scope: "openid masks:manage", resource: resource)
          consent! if awaiting_consent?

          token(
            grant_type: "authorization_code",
            code: code_from,
            redirect_uri: OidcFlow::REDIRECT_URI,
            code_verifier: verifier,
            client_id: @console.client_id
          )["access_token"]
        end
      end

      def ask(query, **variables)
        post "/manage/graphql",
             params: { query: query, variables: variables }.to_json,
             headers: {
               "CONTENT_TYPE" => "application/json",
               "HTTP_AUTHORIZATION" => "Bearer #{bearer}"
             }

        JSON.parse(response.body)
      end

      def probe(**attributes)
        create_client(@tenant, name: "Probe", approved_at: Time.current, **attributes)
      end

      def app_with_namespace
        app = probe(name: "xixo", resources: [ "https://xixo.example.com/mcp" ],
                    token_endpoint_auth_method: "client_secret_basic", grant_types: [ "authorization_code" ])

        within(@tenant) do
          Namespace.create!(name: "xixo:", client: app, resource: app.resources.first, claimed_at: Time.current)
        end

        app
      end

      def enrolled_machine(app)
        within(@tenant) do
          token = EnrollmentToken.issue!(app, scope: "xixo:agent", name: "nas")
          key = OpenSSL::PKey::EC.generate("prime256v1")
          jwks = { "keys" => [ JWT::JWK.new(key, kid: "machine").export.transform_keys(&:to_s) ] }

          EnrollmentToken.redeem!(token.secret, { "client_name" => "nas", "jwks" => jwks })
        end
      end

      MACHINES = <<~GRAPHQL
        query($clientId: ID!) { client(clientId: $clientId) { enrolled { clientId name lastSeenAt } } }
      GRAPHQL

      test "an app's machines are listed with their last sign-in, and one is revoked from the console" do
        app = app_with_namespace
        machine = enrolled_machine(app)

        within(@tenant) { AccessToken.mint!(client: machine, scopes: "xixo:agent", audience: app.resources) }

        listed = ask(MACHINES, clientId: app.client_id).dig("data", "client", "enrolled")

        assert_equal [ machine.client_id ], listed.map { |row| row["clientId"] }
        assert_equal "nas", listed.first["name"]
        assert listed.first["lastSeenAt"].present?

        revoked = ask(<<~GRAPHQL, clientId: machine.client_id)
          mutation($clientId: ID!) {
            unenrollClient(clientId: $clientId) { client { archivedAt enrolledBy { clientId } } }
          }
        GRAPHQL

        assert revoked.dig("data", "unenrollClient", "client", "archivedAt").present?
        assert_equal app.client_id, revoked.dig("data", "unenrollClient", "client", "enrolledBy", "clientId")

        within(@tenant) do
          assert machine.reload.archived?
          assert_equal 0, Token.where(client_id: machine.id, consumed_at: nil).count
          assert Event.where(action: Event::CLIENT_UNENROLLED, client: machine).exists?
        end

        assert_empty ask(MACHINES, clientId: app.client_id).dig("data", "client", "enrolled")
      end

      test "a machine that never got a token has no last sign-in, and an app cannot be unenrolled" do
        app = app_with_namespace
        machine = enrolled_machine(app)

        assert_nil ask(MACHINES, clientId: app.client_id).dig("data", "client", "enrolled", 0, "lastSeenAt")

        refused = ask(<<~GRAPHQL, clientId: app.client_id)
          mutation($clientId: ID!) { unenrollClient(clientId: $clientId) { client { archivedAt } } }
        GRAPHQL

        assert_match(/not a machine/, refused["errors"].to_s)
        within(@tenant) { assert_not app.reload.archived? }
        within(@tenant) { assert_not machine.reload.archived? }
      end

      test "a refresh chain's limit is set from the console, and zero goes back to the default" do
        client = probe

        edit = "mutation Edit($clientId: ID!, $limit: Int) {
          updateClient(clientId: $clientId, refreshTokenAbsoluteLifetime: $limit) {
            client { refreshTokenAbsoluteLifetime }
          }
        }"

        body = ask(edit, clientId: client.client_id, limit: 7.days.to_i)

        assert_nil body["errors"]
        assert_equal 7.days.to_i, body["data"]["updateClient"]["client"]["refreshTokenAbsoluteLifetime"]
        assert_equal 7.days, within { client.reload.refresh_absolute_lifetime }

        body = ask(edit, clientId: client.client_id, limit: 0)

        assert_nil body["data"]["updateClient"]["client"]["refreshTokenAbsoluteLifetime"]
        assert_equal 90.days, within { client.reload.refresh_absolute_lifetime }
      end

      test "the redirect uris a client may use are edited from the console" do
        client = probe

        body = ask(
          "mutation Edit($clientId: ID!, $redirectUris: [String!]) {
        updateClient(clientId: $clientId, redirectUris: $redirectUris) {
          client { redirectUris }
        }
      }",
          clientId: client.client_id,
          redirectUris: [ "https://probe.example.com/cb", "https://probe.example.com/other" ]
        )

        assert_nil body["errors"]
        assert_equal(
          [ "https://probe.example.com/cb", "https://probe.example.com/other" ],
          body["data"]["updateClient"]["client"]["redirectUris"]
        )
      end

      test "a redirect uri that is not usable is refused with a reason" do
        client = probe

        body = ask(
          "mutation Edit($clientId: ID!, $redirectUris: [String!]) {
        updateClient(clientId: $clientId, redirectUris: $redirectUris) { client { clientId } }
      }",
          clientId: client.client_id,
          redirectUris: [ "https://probe.example.com/cb#fragment" ]
        )

        assert_match(/fragment/, body["errors"].to_s)
        assert_equal(
          [ "https://probe.example.com/cb" ],
          within(@tenant) { client.reload.redirect_uris }
        )
      end

      test "a client cannot be left with no redirect uri at all" do
        client = probe

        body = ask(
          "mutation Edit($clientId: ID!, $redirectUris: [String!]) {
        updateClient(clientId: $clientId, redirectUris: $redirectUris) { client { clientId } }
      }",
          clientId: client.client_id,
          redirectUris: []
        )

        assert_match(/at least one/, body["errors"].to_s)
      end

      test "the resources a client may ask a token for are edited from the console" do
        client = probe

        body = ask(
          "mutation Edit($clientId: ID!, $resources: [String!]) {
        updateClient(clientId: $clientId, resources: $resources) { client { resources } }
      }",
          clientId: client.client_id,
          resources: [ "https://api.example.com" ]
        )

        assert_nil body["errors"]
        assert_equal [ "https://api.example.com" ], body["data"]["updateClient"]["client"]["resources"]
      end

      test "an archived client is restored" do
        client = probe
        within(@tenant) { client.update!(archived_at: Time.current) }

        body = ask(
          "mutation Restore($clientId: ID!) {
        restoreClient(clientId: $clientId) { client { archivedAt } }
      }",
          clientId: client.client_id
        )

        assert_nil body["errors"]
        assert_nil body["data"]["restoreClient"]["client"]["archivedAt"]
        assert_nil within(@tenant) { client.reload.archived_at }
        assert within(@tenant) { Event.exists?(action: Event::CLIENT_RESTORED) }
      end

      test "restoring a client is refused when something else answers for its resource now" do
        client = probe(resources: [ "https://api.example.com" ])
        within(@tenant) { client.update!(archived_at: Time.current) }

        create_client(
          @tenant,
          name: "Successor",
          approved_at: Time.current,
          resources: [ "https://api.example.com" ]
        )

        body = ask(
          "mutation Restore($clientId: ID!) {
        restoreClient(clientId: $clientId) { client { archivedAt } }
      }",
          clientId: client.client_id
        )

        assert_match(/Successor/, body["errors"].to_s)
        assert within(@tenant) { client.reload.archived_at.present? }
      end

      test "restoring a client that is not archived is refused" do
        client = probe

        body = ask(
          "mutation Restore($clientId: ID!) {
        restoreClient(clientId: $clientId) { client { archivedAt } }
      }",
          clientId: client.client_id
        )

        assert_match(/not archived/, body["errors"].to_s)
      end
    end
  end
end
