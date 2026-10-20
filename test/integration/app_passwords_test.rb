module Masks
  module Server
    require "test_helper"

    class AppPasswordsTest < ActionDispatch::IntegrationTest
      APP = "https://dash.example.com".freeze
      SECRET = /[a-z2-9]{4}(?:-[a-z2-9]{4}){5}/
      ROLES = Scopes.join(ManageRoles::SCOPES)

      setup do
        host! host_for(@tenant)
        ::Rails.cache.clear

        @actor = create_actor(@tenant, nickname: "ada", email: "ada@example.com", otp: true)
        @dash = proxied(APP, name: "Dash", app_passwords: true)
        @nas = create_client(@tenant, name: "NAS", approved_at: Time.current, app_passwords: true)
      end

      def proxied(origin, **attributes)
        within do
          Client.create!(client_id: SecureRandom.uuid, name: "Dash", protocol: Client::FORWARD,
                         redirect_uris: [ "#{origin}#{Client::FORWARD_CALLBACK}" ], grant_types: [], response_types: [],
                         token_endpoint_auth_method: "none", approved_at: Time.current, **attributes)
        end
      end

      def make(name: "Jellyfin on the TV", client: @nas)
        post "/account/app_passwords", params: { name: name, client_id: client.client_id }
        follow_redirect!

        response.body[SECRET]
      end

      def forwarded(uri, identifier: nil, secret: nil, **params)
        target = URI.parse(uri)
        headers = { "X-Forwarded-Proto" => target.scheme, "X-Forwarded-Host" => target.host,
                    "X-Forwarded-Uri" => target.request_uri }
        headers["Authorization"] = ActionController::HttpAuthentication::Basic.encode_credentials(identifier, secret) if identifier

        get "/forward-auth", params: params, headers: headers
      end

      def events(action)
        within { Event.where(action: action).order(:id).to_a }
      end

      def held
        within { AppPassword.live.where(actor: @actor).to_a }
      end

      test "a person makes an app password for an app that accepts them, and sees it once" do
        sign_in_as(@actor)
        get "/"

        assert_select "#app-passwords"
        assert_select "#app-password-client option", text: "NAS"
        assert_select "#app-password-client option", text: "Dash"

        secret = make

        assert_match SECRET, secret
        assert_select ".codes code", text: secret
        assert_select "#app-passwords .item-name", text: /Jellyfin on the TV/
        assert_select "#app-passwords .tag", text: "NAS"

        get "/"
        assert_select ".codes code", count: 0

        password = held.sole
        assert_equal "Jellyfin on the TV", password.name
        assert_equal @nas.id, password.client_id
        assert_not_equal secret, password.digest
        assert_nil password.used_at

        created = events(Event::APP_PASSWORD_CREATED).sole
        assert_equal @actor.id, created.actor_id
        assert_equal @nas.id, created.client_id
        assert_equal "Jellyfin on the TV", created.details["name"]
      end

      test "an app that does not accept app passwords is neither offered nor given one" do
        plain = create_client(@tenant, name: "Plain", approved_at: Time.current)
        sign_in_as(@actor)

        get "/"
        assert_select "#app-password-client option", text: "Plain", count: 0

        assert_nil make(client: plain)
        assert_equal "That app does not accept app passwords.", flash[:alert]
        assert_empty held
      end

      test "an app that admits only a group is offered to its members alone" do
        within { @nas.update!(allowed_groups: [ "staff" ]) }
        sign_in_as(@actor)

        assert_nil make
        assert_empty held

        staff = within { Group.create!(key: "staff", name: "Staff") }
        within { staff.add!(@actor) }

        assert_match SECRET, make
      end

      test "a name is required and an account holds a bounded number" do
        sign_in_as(@actor)

        assert_nil make(name: "  ")
        assert_equal "Give the app password a name of up to 64 characters.", flash[:alert]

        AppPassword::MOST.times { |index| make(name: "Box #{index}") }

        assert_nil make(name: "One more")
        assert_equal "You already have 20 app passwords. Revoke one first.", flash[:alert]
        assert_equal AppPassword::MOST, held.size
      end

      test "making one needs a fresh sign-in" do
        sign_in_as(@actor)

        travel(Session::FRESHNESS + 1.minute) do
          post "/account/app_passwords", params: { name: "Later", client_id: @nas.client_id }

          assert_redirected_to %r{/login\?return_to=}
          assert_empty held
        end
      end

      test "revoking an app password leaves the account's password and passkeys alone" do
        sign_in_as(@actor)
        make
        password = held.sole

        delete "/account/app_passwords/#{password.id}"
        follow_redirect!

        assert_select "#app-passwords .item-name", count: 0
        assert_empty held
        assert within { Actor.authenticate("ada", "password") }
        assert within { @actor.reload.otp? }

        revoked = events(Event::APP_PASSWORD_REVOKED).sole
        assert_equal "Jellyfin on the TV", revoked.details["name"]

        delete "/account/app_passwords/#{password.id}"
        assert_equal "There is no such app password on this account.", flash[:alert]
      end

      test "somebody else's app password cannot be revoked" do
        sign_in_as(@actor)
        make
        password = held.sole

        reset!
        host! host_for(@tenant)
        sign_in_as(create_actor(@tenant, nickname: "mallory"))

        delete "/account/app_passwords/#{password.id}"

        assert_equal "There is no such app password on this account.", flash[:alert]
        assert_equal 1, held.size
      end

      test "an app password signs in to forward auth over basic auth, without the second factor" do
        sign_in_as(@actor)
        secret = make(client: @dash)
        reset!
        host! host_for(@tenant)

        forwarded("#{APP}/reports", identifier: "ada", secret: secret)

        assert_response :ok
        assert_equal "ada", response.headers["Remote-User"]
        assert_nil response.headers["Set-Cookie"]

        password = held.sole
        assert password.used_at.present?

        used = events(Event::APP_PASSWORD_USED).sole
        assert_equal @dash.id, used.client_id

        forwarded("#{APP}/reports", identifier: "ada", secret: secret.upcase.delete("-"))
        assert_response :ok
        assert_equal 1, events(Event::APP_PASSWORD_USED).size
      end

      test "an app password works only for the app it was made for" do
        sign_in_as(@actor)
        secret = make(client: @nas)
        reset!
        host! host_for(@tenant)

        forwarded("#{APP}/reports", identifier: "ada", secret: secret)

        assert_response :unauthorized
        assert_nil response.headers["Remote-User"]

        refused = events(Event::LOGIN_REFUSED).last
        assert_equal "app_password", refused.details["factor"]
        assert_equal "forward_auth", refused.details["via"]
        assert_equal @actor.id, refused.actor_id
      end

      test "the account password never signs in over basic auth, and an app password never signs in to the browser" do
        sign_in_as(@actor)
        secret = make(client: @dash)
        reset!
        host! host_for(@tenant)
        signed_in_at = within { @actor.reload.last_login_at }

        forwarded("#{APP}/reports", identifier: "ada", secret: "password")
        assert_response :unauthorized

        post "/login", params: { event: "identify", identifier: "ada" }, as: :json
        post "/login", params: { event: "password", password: secret }, as: :json

        assert_equal "first-factor", JSON.parse(response.body)["prompt"]
        assert_equal signed_in_at, within { @actor.reload.last_login_at }
      end

      test "an app password stops working when the app stops accepting them, or the account is suspended" do
        sign_in_as(@actor)
        secret = make(client: @dash)
        reset!
        host! host_for(@tenant)

        within { @dash.update!(app_passwords: false) }
        forwarded("#{APP}/", identifier: "ada", secret: secret)
        assert_response :unauthorized

        within { @dash.update!(app_passwords: true) }
        forwarded("#{APP}/", identifier: "ada", secret: secret)
        assert_response :ok

        within { @actor.suspend!(reason: Actor::MANAGER) }
        forwarded("#{APP}/", identifier: "ada", secret: secret)
        assert_response :unauthorized
        assert_empty held
      end

      test "failed app password attempts count against the account's sign-in limit" do
        sign_in_as(@actor)
        secret = make(client: @dash)
        reset!
        host! host_for(@tenant)
        ::Rails.cache.clear

        ::Rails.configuration.masks.account_attempt_limit.times do
          forwarded("#{APP}/", identifier: "ada", secret: AppPassword.grouped("a" * AppPassword::LENGTH))
          assert_response :unauthorized
        end

        forwarded("#{APP}/", identifier: "ada", secret: secret)
        assert_response :too_many_requests
        assert events(Event::LOGIN_THROTTLED).any?

        post "/login", params: { event: "identify", identifier: "ada" }, as: :json
        post "/login", params: { event: "password", password: "password" }, as: :json
        assert_response :too_many_requests
      end

      test "a manager turns app passwords on for a client" do
        owner = create_actor(@tenant, nickname: "owner", scopes: "openid profile email masks:manage")
        console = create_client(@tenant, name: "Console", allowed_scopes: "openid profile email #{ROLES}",
                                         approved_at: Time.current, grant_types: [ "authorization_code" ])
        plain = create_client(@tenant, name: "Plain", approved_at: Time.current)
        bearer = manage_bearer(owner, console)

        asked = manage(<<~GRAPHQL, bearer: bearer, clientId: plain.client_id)
          mutation Accept($clientId: ID!) {
            updateClient(clientId: $clientId, appPasswords: true) { client { appPasswords } }
          }
        GRAPHQL

        assert_equal true, asked.dig("data", "updateClient", "client", "appPasswords")
        assert within { plain.reload.app_passwords? }

        asked = manage(<<~GRAPHQL, bearer: bearer, clientId: plain.client_id)
          query Shown($clientId: ID!) { client(clientId: $clientId) { appPasswords } }
        GRAPHQL

        assert_equal true, asked.dig("data", "client", "appPasswords")
      end
    end
  end
end
