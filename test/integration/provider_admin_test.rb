module Masks
  module Server
    require "test_helper"

    class ProviderAdminTest < ActionDispatch::IntegrationTest
      CREATE = <<~GQL.freeze
        mutation Add(
          $key: ID!, $name: String!, $authorizationUrl: String!, $tokenUrl: String!,
          $clientId: String!, $clientSecret: String, $scopes: [String!],
          $authorizeParams: JSON, $issuer: String
        ) {
          createProvider(
            key: $key, name: $name, authorizationUrl: $authorizationUrl, tokenUrl: $tokenUrl,
            clientId: $clientId, clientSecret: $clientSecret, scopes: $scopes,
            authorizeParams: $authorizeParams, issuer: $issuer
          ) {
            provider { key name secretHeld scopes connections }
          }
        }
      GQL

      setup do
        host! host_for(@tenant)

        @admin = create_actor(@tenant, nickname: "admin", scopes: "openid profile email masks:manage")
        @client = create_client(
          @tenant,
          allowed_scopes: "openid profile email masks:manage",
          approved_at: Time.current,
          grant_types: [ "authorization_code", "refresh_token" ]
        )
      end

      def token!
        sign_in_as(@admin)
        authorize(
          client_id: @client.client_id,
          scope: "openid masks:manage",
          resource: issuer_for(@tenant).manage_resource
        )
        consent! if awaiting_consent?

        token(
          grant_type: "authorization_code",
          code: code_from,
          redirect_uri: OidcFlow::REDIRECT_URI,
          code_verifier: verifier,
          client_id: @client.client_id
        )["access_token"]
      end

      def ask(query, **variables)
        @token ||= token!

        post "/manage/graphql",
             params: { query: query, variables: variables }.to_json,
             headers: {
               "CONTENT_TYPE" => "application/json",
               "HTTP_AUTHORIZATION" => "Bearer #{@token}"
             }

        JSON.parse(response.body)
      end

      def add(**overrides)
        ask(
          CREATE,
          **{
            key: "google",
            name: "Google",
            issuer: "https://accounts.google.com",
            authorizationUrl: "https://accounts.google.com/o/oauth2/v2/auth",
            tokenUrl: "https://oauth2.googleapis.com/token",
            clientId: "upstream-client",
            clientSecret: "upstream-secret",
            scopes: [ "https://www.googleapis.com/auth/drive.readonly" ]
          }.merge(overrides)
        )
      end

      test "a provider added through the console holds its secret and connects nobody yet" do
        answer = add

        assert_nil answer["errors"]

        held = answer["data"]["createProvider"]["provider"]

        assert held["secretHeld"], "the secret was stored"
        assert_equal 0, held["connections"]
      end

      test "a preset is enough to add github, and the console is told where to send people back" do
        answer = ask(<<~GQL)
          mutation {
            createProvider(key: "github", name: "GitHub", preset: "github", clientId: "gh", clientSecret: "shh") {
              provider { key protocol preset userinfoUrl emailsUrl subjectClaim trustsEmail callbackUrl }
            }
          }
        GQL

        assert_nil answer["errors"]

        held = answer.dig("data", "createProvider", "provider")

        assert_equal "oauth2", held["protocol"]
        assert_equal "github", held["preset"]
        assert_equal "https://api.github.com/user/emails", held["emailsUrl"]
        assert_equal "id", held["subjectClaim"]
        assert held["trustsEmail"]
        assert held["callbackUrl"].end_with?("/login/provider/github/callback")
      end

      test "a preset that asks for something refuses to be added without it" do
        answer = ask(%(mutation { createProvider(key: "okta", name: "Okta", preset: "okta", clientId: "o") { provider { key } } }))

        assert_match "needs a domain", answer["errors"].first["message"]
      end

      test "the presets are listed with what each one asks for" do
        held = ask("{ providerPresets { key protocol asks needs } }").dig("data", "providerPresets")

        assert_equal %w[team_id key_id private_key], held.find { |one| one["key"] == "apple" }["needs"]
        assert_equal %w[domain realm], held.find { |one| one["key"] == "keycloak" }["asks"]
        assert_equal "mcp", held.find { |one| one["key"] == "notion" }["protocol"]
      end

      test "a provider lets applications use it only when it names what they may do" do
        refused = ask(%(mutation { updateProvider(key: "google", delegates: true) { provider { key } } })) if add.dig("data", "createProvider")

        assert_match "must name what applications may do", refused["errors"].first["message"]

        answer = ask(<<~GQL)
          mutation {
            updateProvider(key: "google", delegates: true, delegatedScopes: ["https://www.googleapis.com/auth/drive.readonly"],
                           delegationParams: { access_type: "offline" }) {
              provider { delegates delegatedScopes delegationParams delegationScope delegations }
            }
          }
        GQL

        held = answer.dig("data", "updateProvider", "provider")

        assert held["delegates"]
        assert_equal [ "https://www.googleapis.com/auth/drive.readonly" ], held["delegatedScopes"]
        assert_equal({ "access_type" => "offline" }, held["delegationParams"])
        assert_equal "masks:delegate:google", held["delegationScope"]
        assert_equal 0, held["delegations"]
      end

      test "a delegation is revoked through the manage API" do
        add
        @token ||= token!

        delegation = within(@tenant) do
          provider = Provider.find_by!(key: "google")
          provider.update!(delegates: true, delegated_scopes: "drive")
          connection = Connection.record!(provider: provider, actor: @admin, identity: { "sub" => "g-1" })
          connection.update!(refresh_token: "held", delegated_scopes: "drive")

          Delegation.grant!(client: @client, actor: @admin, connection: connection)
        end

        answer = ask(%(mutation { revokeDelegation(id: "#{delegation.uuid}") { delegation { revokedAt client { name } provider { key } } } }))

        assert answer.dig("data", "revokeDelegation", "delegation", "revokedAt"), answer.inspect
        assert within(@tenant) { delegation.reload.revoked? }
        assert_equal 1, within(@tenant) { Event.where(action: Event::DELEGATION_REVOKED).count }
      end

      test "the secret is stored but never handed back" do
        add

        answer = ask("query One($key: ID!) { provider(key: $key) { name secretHeld } }", key: "google")

        assert_equal "Google", answer["data"]["provider"]["name"]
        assert answer["data"]["provider"]["secretHeld"]
        assert_not response.body.include?("upstream-secret"),
                   "a client secret has no business leaving the server"
      end

      test "a token endpoint over plain http is refused unless it is loopback" do
        answer = add(tokenUrl: "http://accounts.example.com/token")

        assert_not_nil answer["errors"]
        assert_match(/https/, answer["errors"].first["message"])
        assert_equal 0, within(@tenant) { Provider.count }
      end

      test "loopback is allowed, because that is what running one locally looks like" do
        answer = add(tokenUrl: "http://127.0.0.1:9999/token")

        assert_nil answer["errors"]
      end

      test "authorize params may not take over the parameters the request builds" do
        answer = add(authorizeParams: { "redirect_uri" => "https://elsewhere.example.com/cb" })

        assert_not_nil answer["errors"]
        assert_match(/redirect_uri/, answer["errors"].first["message"])
      end

      test "authorize params carry the extras a provider asks for" do
        answer = add(authorizeParams: { "access_type" => "offline", "prompt" => "consent" })

        assert_nil answer["errors"]

        location = within(@tenant) do
          Provider.find_by!(key: "google").authorize_url(redirect_uri: "https://masks.test/cb", state: "s")
        end

        assert_includes location, "access_type=offline"
        assert_includes location, "prompt=consent"
      end

      test "a key is claimed once" do
        add

        answer = add(name: "Google Again")

        assert_not_nil answer["errors"]
        assert_match(/already keyed/, answer["errors"].first["message"])
      end

      test "editing leaves the secret alone unless a new one is sent" do
        add

        answer = ask(<<~GQL, key: "google", name: "Google Workspace")
          mutation Edit($key: ID!, $name: String!) {
            updateProvider(key: $key, name: $name) { provider { name secretHeld } }
          }
        GQL

        assert_nil answer["errors"]
        assert_equal "Google Workspace", answer["data"]["updateProvider"]["provider"]["name"]
        assert answer["data"]["updateProvider"]["provider"]["secretHeld"]

        assert_equal "upstream-secret", within(@tenant) { Provider.find_by(key: "google").client_secret }
      end

      test "archiving takes the provider out of reach, and restoring puts it back" do
        add

        assert_nil ask("mutation Off($key: ID!) { archiveProvider(key: $key) { provider { key } } }",
                       key: "google")["errors"]

        assert_empty within(@tenant) { Provider.active.to_a }

        assert_nil ask("mutation On($key: ID!) { restoreProvider(key: $key) { provider { key } } }",
                       key: "google")["errors"]

        assert_equal [ "google" ], within(@tenant) { Provider.active.pluck(:key) }
      end

      test "adding, editing and archiving a provider are all written down" do
        add
        ask("mutation Edit($key: ID!, $name: String!) { updateProvider(key: $key, name: $name) { provider { key } } }",
            key: "google", name: "Workspace")
        ask("mutation Off($key: ID!) { archiveProvider(key: $key) { provider { key } } }", key: "google")

        actions = within(@tenant) do
          Event.where(action: [ Event::PROVIDER_CREATED, Event::PROVIDER_UPDATED, Event::PROVIDER_ARCHIVED ])
               .newest_first.map(&:action)
        end

        assert_equal [ Event::PROVIDER_ARCHIVED, Event::PROVIDER_UPDATED, Event::PROVIDER_CREATED ], actions

        assert_equal @admin.id, within(@tenant) { Event.where(action: Event::PROVIDER_CREATED).first.by_id }
      end
    end
  end
end
