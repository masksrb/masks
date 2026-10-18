module Masks
  module Server
    require "test_helper"

    class SignOutEverywhereTest < ActionDispatch::IntegrationTest
      setup do
        host! host_for(@tenant)
        @actor = create_actor(@tenant, email: "owner@example.com", email_verified_at: Time.current)
        @registration = register(@tenant, grant_types: [ "authorization_code", "refresh_token", DeviceGrant::GRANT_TYPE ])
      end

      def active?(access_token)
        post "/introspect", params: { token: access_token },
                            headers: { "HTTP_AUTHORIZATION" => "Basic #{Base64.strict_encode64("#{@registration["client_id"]}:#{@registration["client_secret"]}")}" }

        JSON.parse(response.body)["active"]
      end

      def signed_in_token
        code = authorized_code(actor: @actor, registration: @registration, scope: "openid profile")

        token(grant_type: "authorization_code", code: code, redirect_uri: REDIRECT_URI, code_verifier: verifier,
              client_id: @registration["client_id"], client_secret: @registration["client_secret"])
      end

      def device_token
        post "/device_authorization", params: { client_id: @registration["client_id"], client_secret: @registration["client_secret"], scope: "openid profile" }
        held = JSON.parse(response.body)

        sign_in_as(@actor)
        get "/device?#{URI.encode_www_form(user_code: held["user_code"])}"
        consent! if awaiting_consent?

        travel DeviceGrant::INTERVAL.seconds + 1.second

        token(grant_type: DeviceGrant::GRANT_TYPE, device_code: held["device_code"],
              client_id: @registration["client_id"], client_secret: @registration["client_secret"])
      end

      test "a token with no refresh token behind it ends with everything else" do
        issued = signed_in_token

        assert_nil issued["refresh_token"]
        assert active?(issued["access_token"])

        within { @actor.sign_out_everywhere! }

        refute active?(issued["access_token"])
      end

      test "a device's token ends too" do
        issued = device_token

        assert active?(issued["access_token"])

        within { @actor.sign_out_everywhere! }

        refute active?(issued["access_token"])
      end

      test "a password reset ends every token" do
        issued = signed_in_token

        within { @actor.reset_password!("a much longer passphrase") }

        refute active?(issued["access_token"])
      end

      test "a manager resetting second factors ends every token" do
        issued = signed_in_token
        manager = create_actor(@tenant, nickname: "manager", scopes: "masks:manage")

        within { HelpRequests.reset!(@actor, by: manager) }

        refute active?(issued["access_token"])
      end

      test "changing the password keeps the token of the session it happened in, and ends the rest" do
        elsewhere = signed_in_token

        reset!
        host! host_for(@tenant)
        here = signed_in_token

        patch "/account/password", params: { current_password: "password", password: "a much longer passphrase" }

        assert_redirected_to "/"
        refute active?(elsewhere["access_token"])
        assert active?(here["access_token"])
      end
    end
  end
end
