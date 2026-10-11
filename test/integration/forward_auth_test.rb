module Masks
  module Server
    require "test_helper"

    class ForwardAuthTest < ActionDispatch::IntegrationTest
      APP = "https://dash.example.com".freeze

      setup do
        host! host_for(@tenant)
        @actor = create_actor(nickname: "ada", email: "ada@example.com", name: "Ada")
        within { @actor.update!(email_verified_at: Time.current) }
        @client = proxied(APP)
      end

      def proxied(origin, **attributes)
        within do
          Client.create!(client_id: SecureRandom.uuid, name: "Dash", protocol: Client::FORWARD,
                         redirect_uris: [ "#{origin}#{Client::FORWARD_CALLBACK}" ], grant_types: [], response_types: [],
                         token_endpoint_auth_method: "none", approved_at: Time.current, **attributes)
        end
      end

      def forwarded(uri, cookie: nil, **params)
        target = URI.parse(uri)
        headers = { "X-Forwarded-Proto" => target.scheme, "X-Forwarded-Host" => target.host,
                    "X-Forwarded-Uri" => target.request_uri }
        headers["Cookie"] = "#{ForwardSession::COOKIE}=#{cookie}" if cookie

        get "/forward-auth", params: params, headers: headers
      end

      def set_cookie
        Array(response.headers["Set-Cookie"]).flat_map { |line| line.split("\n") }
      end

      def handed_cookie
        set_cookie.find { |line| line.start_with?("#{ForwardSession::COOKIE}=") }&.then { |line| line[/=([^;]+)/, 1] }
      end

      def round_trip(path = "/reports")
        forwarded("#{APP}#{path}")
        get response.location

        callback = response.location
        forwarded(callback)

        handed_cookie
      end

      test "a visitor without the app's cookie is sent to sign in through masks" do
        forwarded("#{APP}/reports?week=2")

        assert_response :redirect
        assert_equal "/forward-auth/start", URI.parse(response.location).path
        assert_equal "#{APP}/reports?week=2", Rack::Utils.parse_query(URI.parse(response.location).query)["rd"]
      end

      test "nginx asks for a 401 instead of a redirect" do
        forwarded("#{APP}/", status: "401")

        assert_response :unauthorized
      end

      test "someone not signed in to masks signs in first" do
        get "/forward-auth/start", params: { rd: "#{APP}/reports" }

        assert_redirected_to %r{/login\?return_to=}
      end

      test "a signed-in person reaches the app, which learns who they are" do
        sign_in_as(@actor)
        secret = round_trip

        assert_equal "#{APP}/reports", response.location
        assert secret.present?
        assert set_cookie.none? { |line| line.start_with?("masks_session") }, "the app's host never gets masks' own cookie"

        forwarded("#{APP}/reports", cookie: secret)

        assert_response :ok
        assert_equal "ada", response.headers["Remote-User"]
        assert_equal "ada@example.com", response.headers["Remote-Email"]
        assert_equal "Ada", response.headers["Remote-Name"]
      end

      test "signing out of masks ends the app's cookie too" do
        sign_in_as(@actor)
        secret = round_trip

        delete "/login"
        within { Session.where(actor: @actor).find_each(&:revoke!) }

        forwarded("#{APP}/reports", cookie: secret)

        assert_response :redirect
      end

      test "an app's cookie does not open another app" do
        other = "https://other.example.com"
        proxied(other)
        sign_in_as(@actor)
        secret = round_trip

        forwarded("#{other}/", cookie: secret)

        assert_response :redirect
      end

      test "a code is good once, and only at the app it was made for" do
        proxied("https://other.example.com")
        sign_in_as(@actor)
        forwarded("#{APP}/")
        get response.location
        code = Rack::Utils.parse_query(URI.parse(response.location).query)["code"]

        forwarded("https://other.example.com#{Client::FORWARD_CALLBACK}?code=#{code}")
        assert_response :forbidden

        forwarded("#{APP}#{Client::FORWARD_CALLBACK}?code=#{code}")
        assert_response :forbidden
      end

      test "an app limited to a group turns away someone outside it" do
        within { @client.update!(allowed_groups: %w[admins]) }
        sign_in_as(@actor)

        get "/forward-auth/start", params: { rd: "#{APP}/" }

        assert_response :forbidden
      end

      test "an address no app is registered at is refused" do
        forwarded("https://unknown.example.com/")

        assert_response :forbidden
      end

      test "nginx hands the callback to its own endpoint" do
        sign_in_as(@actor)
        forwarded("#{APP}/reports")
        get response.location
        code = Rack::Utils.parse_query(URI.parse(response.location).query)["code"]

        get "/forward-auth/callback", params: { code: code },
                                      headers: { "X-Forwarded-Proto" => "https", "X-Forwarded-Host" => "dash.example.com" }

        assert_redirected_to "#{APP}/reports"
        assert handed_cookie.present?
      end

      test "a return address nginx could not encode comes back whole" do
        sign_in_as(@actor)

        get "/forward-auth/start?rd=#{APP}/r?a=1&b=2"
        forwarded(response.location)

        assert_equal "#{APP}/r?a=1&b=2", response.location
      end
    end
  end
end
