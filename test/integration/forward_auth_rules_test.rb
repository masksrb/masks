module Masks
  module Server
    require "test_helper"

    class ForwardAuthRulesTest < ActionDispatch::IntegrationTest
      APP = "https://dash.example.com".freeze
      PROXY = "10.0.0.2".freeze
      HOME = "192.168.1.5".freeze
      AWAY = "203.0.113.9".freeze

      setup do
        host! host_for(@tenant)
        @actor = create_actor(nickname: "ada", email: "ada@example.com", name: "Ada", otp: false)
        @client = proxied(APP)
      end

      def proxied(origin, **attributes)
        within do
          Client.create!(client_id: SecureRandom.uuid, name: "Dash", protocol: Client::FORWARD,
                         redirect_uris: [ "#{origin}#{Client::FORWARD_CALLBACK}" ], grant_types: [], response_types: [],
                         token_endpoint_auth_method: "none", approved_at: Time.current, **attributes)
        end
      end

      def rule!(*rules)
        within { @client.update!(forward_auth_rules: rules) }
      end

      def forwarded(uri, cookie: nil, from: nil, peer: PROXY, method: nil, bearer: nil, **params)
        target = URI.parse(uri)
        headers = { "X-Forwarded-Proto" => target.scheme, "X-Forwarded-Host" => target.host,
                    "X-Forwarded-Uri" => target.request_uri, "REMOTE_ADDR" => peer }
        headers["X-Forwarded-For"] = from if from
        headers["X-Forwarded-Method"] = method if method
        headers["Cookie"] = "#{ForwardSession::COOKIE}=#{cookie}" if cookie
        headers["Authorization"] = "Bearer #{bearer}" if bearer

        get "/forward-auth", params: params, headers: headers
      end

      def browsing_from(address)
        integration_session.remote_addr = address
      end

      def handed_cookie
        Array(response.headers["Set-Cookie"]).flat_map { |line| line.split("\n") }
          .find { |line| line.start_with?("#{ForwardSession::COOKIE}=") }&.then { |line| line[/=([^;]+)/, 1] }
      end

      def finish(from: nil)
        get response.location
        forwarded(response.location, from: from)

        handed_cookie
      end

      def round_trip(path = "/reports", from: nil)
        forwarded("#{APP}#{path}", from: from)

        finish(from: from)
      end

      def identify
        post "/login", params: { event: "identify", identifier: @actor.nickname }, as: :json
        post "/login", params: { event: "password", password: "password" }, as: :json

        JSON.parse(response.body)
      end

      test "an open path answers everyone, and names the person when it knows them" do
        rule!({ "paths" => [ "/share/**" ], "outcome" => "open" })

        forwarded("#{APP}/share/photo.jpg")

        assert_response :ok
        assert_nil response.headers["Remote-User"]

        sign_in_as(@actor)
        secret = round_trip
        forwarded("#{APP}/share/photo.jpg", cookie: secret)

        assert_response :ok
        assert_equal "ada", response.headers["Remote-User"]

        forwarded("#{APP}/reports", cookie: secret)

        assert_response :ok
        assert_equal "ada", response.headers["Remote-User"]
      end

      test "an open path never names someone the app may not admit, and sends them straight back" do
        within { @client.update!(allowed_groups: %w[admins]) }
        rule!({ "paths" => [ "/share/**" ], "outcome" => "open" })
        sign_in_as(@actor)

        forwarded("#{APP}/share/x")
        assert_response :ok
        assert_nil response.headers["Remote-User"]

        get "/forward-auth/start", params: { rd: "#{APP}/share/x" }
        assert_redirected_to "#{APP}/share/x"

        get "/forward-auth/start", params: { rd: "#{APP}/reports" }
        assert_response :forbidden
      end

      test "a denied path turns everyone away, signed in or not" do
        rule!({ "paths" => [ "/admin/**" ], "outcome" => "deny" })

        forwarded("#{APP}/admin/users")
        assert_response :forbidden

        sign_in_as(@actor)
        secret = round_trip
        forwarded("#{APP}/admin/users", cookie: secret)
        assert_response :forbidden

        get "/forward-auth/start", params: { rd: "#{APP}/admin/users" }
        assert_response :forbidden
        assert_match "closed to everyone", response.body
      end

      test "a method rule covers only the methods it names" do
        rule!({ "paths" => [ "/api/**" ], "methods" => [ "GET", "HEAD" ], "outcome" => "open" })

        forwarded("#{APP}/api/items", method: "GET")
        assert_response :ok

        forwarded("#{APP}/api/items", method: "POST")
        assert_response :redirect

        forwarded("#{APP}/api/items")
        assert_response :ok
      end

      test "a rule for a group waits for a sign-in, then covers only its members" do
        within { Group.create!(key: "admins", name: "Admins").add!(@actor) }
        rule!({ "groups" => [ "admins" ], "outcome" => "deny" }, { "outcome" => "open" })

        forwarded("#{APP}/")
        assert_response :redirect

        sign_in_as(@actor)
        forwarded("#{APP}/")
        get response.location
        assert_response :forbidden

        other = create_actor(nickname: "bob", otp: false)
        delete "/login"
        sign_in_as(other)
        forwarded("#{APP}/", cookie: round_trip)
        assert_response :ok
        assert_equal "bob", response.headers["Remote-User"]
      end

      test "a rule never lets in someone outside the groups that may sign in" do
        within { @client.update!(allowed_groups: %w[admins]) }
        rule!({ "outcome" => "one_factor" })
        sign_in_as(@actor)

        forwarded("#{APP}/")
        get response.location

        assert_response :forbidden
        assert_match "may not use", response.body
      end

      test "a one factor rule on the home network signs someone in without their second factor" do
        enable_otp(@actor)
        rule!({ "networks" => [ "192.168.0.0/16" ], "outcome" => "one_factor" })
        browsing_from(HOME)

        forwarded("#{APP}/reports", from: HOME)
        get response.location
        assert_redirected_to %r{/login\?return_to=}

        body = identify
        refute_equal "second-factor", body["prompt"]

        get "/forward-auth/start", params: { rd: "#{APP}/reports" }
        forwarded(response.location, from: HOME)
        secret = handed_cookie

        forwarded("#{APP}/reports", cookie: secret, from: HOME)
        assert_response :ok
        assert_equal "ada", response.headers["Remote-User"]
        refute_includes within { Session.where(actor: @actor).order(:created_at).last.amr }, Issuer::MULTI_FACTOR
      end

      test "away from home the same person is asked for their second factor" do
        enable_otp(@actor)
        rule!({ "networks" => [ "192.168.0.0/16" ], "outcome" => "one_factor" })
        browsing_from(AWAY)

        forwarded("#{APP}/reports", from: AWAY)
        get response.location

        assert_equal "second-factor", identify["prompt"]
      end

      test "a session let in without its second factor counts for nothing outside a one factor rule" do
        enable_otp(@actor)
        rule!({ "networks" => [ "192.168.0.0/16" ], "outcome" => "one_factor" })
        other = "https://other.example.com"
        proxied(other)
        browsing_from(HOME)

        forwarded("#{APP}/reports", from: HOME)
        get response.location
        identify
        get "/forward-auth/start", params: { rd: "#{APP}/reports" }
        forwarded(response.location, from: HOME)
        relaxed = handed_cookie
        assert within { Session.where(actor: @actor).order(:created_at).last.second_factor_skipped? }

        browsing_from(AWAY)
        forwarded("#{APP}/reports", cookie: relaxed, from: AWAY)
        assert_response :redirect

        get "/forward-auth/start", params: { rd: "#{other}/" }
        assert_redirected_to %r{/login\?return_to=}
        get "/login"
        assert_equal "second-factor", auth_data["prompt"]

        post "/login", params: { event: "otp", code: current_code(@actor) }, as: :json
        refute within { Session.where(actor: @actor).order(:created_at).last.second_factor_skipped? }
      end

      test "a session let in without its second factor is asked for it by an app that signs in with OpenID Connect" do
        enable_otp(@actor)
        rule!({ "outcome" => "one_factor" })
        app = create_client(@tenant, name: "Notes", approved_at: Time.current, consent_required: false, allowed_scopes: "openid profile email",
                                     grant_types: [ "authorization_code" ])

        forwarded("#{APP}/")
        get response.location
        identify
        get "/forward-auth/start", params: { rd: "#{APP}/" }
        assert_match Client::FORWARD_CALLBACK, response.location

        authorize(client_id: app.client_id)
        follow_redirect! while response.redirect? && URI.parse(response.location).host == host

        assert_equal "second-factor", auth_data&.dig("prompt")
      end

      test "a two factor path steps up a session that was let in with one factor" do
        enable_otp(@actor)
        rule!({ "paths" => [ "/admin/**" ], "outcome" => "two_factor" }, { "outcome" => "one_factor" })

        forwarded("#{APP}/reports")
        get response.location
        identify
        get "/forward-auth/start", params: { rd: "#{APP}/reports" }
        forwarded(response.location)
        relaxed = handed_cookie

        forwarded("#{APP}/reports", cookie: relaxed)
        assert_response :ok

        forwarded("#{APP}/admin/users", cookie: relaxed)
        assert_response :redirect

        get response.location
        assert_redirected_to %r{/login\?return_to=}
        get "/login"
        assert_equal "second-factor", auth_data["prompt"]

        post "/login", params: { event: "otp", code: current_code(@actor) }, as: :json
        assert_includes within { Session.where(actor: @actor).order(:created_at).last.amr }, Issuer::MULTI_FACTOR

        get "/forward-auth/start", params: { rd: "#{APP}/admin/users" }
        forwarded(response.location)
        stepped = handed_cookie

        forwarded("#{APP}/admin/users", cookie: stepped)
        assert_response :ok
        assert_equal "ada", response.headers["Remote-User"]

        forwarded("#{APP}/admin/users", cookie: relaxed)
        assert_response :ok
      end

      test "a two factor path lets in someone who has no second factor to give" do
        rule!({ "outcome" => "two_factor" })
        sign_in_as(@actor)

        forwarded("#{APP}/", cookie: round_trip)

        assert_response :ok
      end

      test "a token path lets a script in with an access token for the app, and nobody else" do
        https!
        rule!({ "paths" => [ "/api/**" ], "outcome" => "token" })
        script = within do
          held = Client.new(client_id: SecureRandom.uuid, name: "Nightly", grant_types: [ Client::CLIENT_CREDENTIALS ],
                            response_types: [], resources: [ APP ], allowed_scopes: "dash:read", approved_at: Time.current,
                            token_endpoint_auth_method: "client_secret_post")
          held.issue_secret!
          held.save!
          held
        end
        body = token(grant_type: Client::CLIENT_CREDENTIALS, client_id: script.client_id, client_secret: script.secret,
                     resource: APP)
        minted = body["access_token"]
        assert minted.present?, body.inspect

        forwarded("#{APP}/api/items", bearer: minted)
        assert_response :ok
        assert_equal script.client_id, response.headers["Remote-User"]
        assert_equal "Nightly", response.headers["Remote-Name"]

        forwarded("#{APP}/api/items")
        assert_response :unauthorized
        assert_match "Bearer realm=", response.headers["WWW-Authenticate"]

        forwarded("#{APP}/api/items", bearer: "not-a-token")
        assert_response :unauthorized

        elsewhere = within { script.update!(resources: [ "https://other.example.com" ]) }
        assert elsewhere
        minted = token(grant_type: Client::CLIENT_CREDENTIALS, client_id: script.client_id, client_secret: script.secret,
                       resource: "https://other.example.com")["access_token"]
        forwarded("#{APP}/api/items", bearer: minted)
        assert_response :unauthorized

        sign_in_as(@actor)
        forwarded("#{APP}/api/items", cookie: round_trip)
        assert_response :ok
        assert_equal "ada", response.headers["Remote-User"]
      end

      test "a network rule reads the address the proxy forwarded, and nothing a visitor sends on their own" do
        rule!({ "networks" => [ "192.168.0.0/16" ], "outcome" => "open" })

        forwarded("#{APP}/", from: HOME)
        assert_response :ok

        forwarded("#{APP}/", from: AWAY)
        assert_response :redirect

        forwarded("#{APP}/", from: "#{HOME}, #{AWAY}")
        assert_response :redirect

        forwarded("#{APP}/", from: HOME, peer: AWAY)
        assert_response :redirect
      end

      test "the rules are set and read through the manage API, and a bad one is refused" do
        owner = create_actor(nickname: "boss", scopes: "openid profile email masks:manage")
        console = create_client(@tenant, allowed_scopes: "openid profile email masks:manage", approved_at: Time.current,
                                         grant_types: [ "authorization_code" ])
        bearer = manage_bearer(owner, console)
        change = <<~GQL
          mutation Rules($id: ID!, $rules: JSON!) {
            updateClient(clientId: $id, forwardAuthRules: $rules) { client { forwardAuthRules } }
          }
        GQL

        saved = manage(change, bearer: bearer, id: @client.client_id,
                               rules: [ { paths: [ " /admin/** " ], methods: [ "post" ], networks: [ "10.0.0.0/8" ],
                                          groups: [ "Admins" ], outcome: "Two_Factor" } ])
        assert_nil saved["errors"]
        assert_equal [ { "paths" => [ "/admin/**" ], "methods" => [ "POST" ], "networks" => [ "10.0.0.0/8" ],
                         "groups" => [ "admins" ], "outcome" => "two_factor" } ],
                     saved.dig("data", "updateClient", "client", "forwardAuthRules")

        read = manage("query Read($id: ID!) { client(clientId: $id) { forwardAuthRules } }", bearer: bearer, id: @client.client_id)
        assert_equal "two_factor", read.dig("data", "client", "forwardAuthRules", 0, "outcome")

        refused = manage(change, bearer: bearer, id: @client.client_id, rules: [ { networks: [ "home" ], outcome: "open" } ])
        assert_match "rule 1 has a network of \"home\"", refused.dig("errors", 0, "message").to_s

        refused = manage(change, bearer: bearer, id: @client.client_id, rules: [ { paths: [ "admin" ], outcome: "open" } ])
        assert_match "does not start with /", refused.dig("errors", 0, "message").to_s

        refused = manage(change, bearer: bearer, id: @client.client_id, rules: [ { methods: [ "FETCH" ], outcome: "open" } ])
        assert_match "names a method of \"FETCH\"", refused.dig("errors", 0, "message").to_s

        refused = manage(change, bearer: bearer, id: @client.client_id, rules: [ { outcome: "maybe" } ])
        assert_match "has an outcome of \"maybe\"", refused.dig("errors", 0, "message").to_s

        refused = manage(change, bearer: bearer, id: console.client_id, rules: [ { outcome: "open" } ])
        assert_match "apply only to an app behind a proxy", refused.dig("errors", 0, "message").to_s

        cleared = manage(change, bearer: bearer, id: @client.client_id, rules: [])
        assert_equal [], cleared.dig("data", "updateClient", "client", "forwardAuthRules")
      end
    end
  end
end
