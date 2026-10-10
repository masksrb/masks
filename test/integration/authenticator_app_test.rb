module Masks
  module Server
    require "test_helper"

    class AuthenticatorAppTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper

      setup do
        host! host_for(@tenant)
        policy!

        @actor = create_actor(@tenant, nickname: "ada", email: "ada@example.com")
      end

      def policy!(factors = %w[otp passkey backup_codes])
        within(@tenant) do
          SignInPolicy.create!(key: "factors-#{SecureRandom.hex(2)}", name: "Factors", second_factors: factors)
        end.tap { |held| @tenant.update!(sign_in_policy: held) }
      end

      def shown_secret
        get "/"

        response.body[%r{<code class="enrol-secret">([^<]+)</code>}, 1].to_s.delete(" ")
      end

      def shown_codes
        response.body.scan(%r{<li><code>([^<]+)</code></li>}).flatten
      end

      def reloaded
        within(@tenant) { @actor.reload }
      end

      test "a person sets up an authenticator app from the account page and gets backup codes" do
        sign_in_as(@actor)
        secret = shown_secret

        assert_equal 32, secret.length

        perform_enqueued_jobs do
          post "/account/authenticator", params: { code: ROTP::TOTP.new(secret).now }
        end

        assert_redirected_to "/#authenticator"
        assert reloaded.otp?

        follow_redirect!

        assert_equal 10, shown_codes.length
        assert within(@tenant) { reloaded.verify_backup_code(shown_codes.first) }
        assert within(@tenant) { Event.where(action: Event::AUTHENTICATOR_ENABLED, actor: @actor).exists? }
      end

      test "a wrong code leaves the account as it was and keeps the same key" do
        sign_in_as(@actor)
        secret = shown_secret

        post "/account/authenticator", params: { code: "000000" }

        assert_equal flash[:alert], I18n.t("authenticator_apps.invalid_code")
        refute reloaded.otp?
        assert_equal secret, shown_secret
      end

      test "a key shown to one person is not used for another signed in afterwards" do
        sign_in_as(@actor)
        secret = shown_secret

        delete "/login"
        other = create_actor(@tenant, nickname: "grace")
        sign_in_as(other)

        refute_equal secret, shown_secret
      end

      test "setting one up asks for a recent sign-in" do
        sign_in_as(@actor)
        secret = shown_secret

        travel 16.minutes do
          post "/account/authenticator", params: { code: ROTP::TOTP.new(secret).now }

          assert_redirected_to %r{/login}
          refute reloaded.otp?
        end
      end

      test "a server that does not offer authenticator apps shows no setup and refuses one" do
        policy!(%w[passkey])
        sign_in_as(@actor)

        get "/"

        assert_no_match "enrol-secret", response.body

        post "/account/authenticator", params: { code: "123456" }

        assert_equal flash[:alert], I18n.t("authenticator_apps.unoffered")
      end

      test "removing the app drops backup codes when nothing else needs them" do
        enable_otp(@actor)
        within(@tenant) { @actor.reload.generate_backup_codes! }
        sign_in_as(@actor)

        delete "/account/authenticator"

        assert_redirected_to "/#authenticator"
        refute reloaded.otp?
        refute reloaded.backup_codes?
        assert within(@tenant) { Event.where(action: Event::AUTHENTICATOR_DISABLED, actor: @actor).exists? }
      end

      test "new backup codes replace the old ones" do
        enable_otp(@actor)
        old = within(@tenant) { @actor.reload.generate_backup_codes! }
        sign_in_as(@actor)

        post "/account/backup_codes"
        follow_redirect!

        assert_equal 10, shown_codes.length
        refute within(@tenant) { reloaded.verify_backup_code(old.first) }
        assert within(@tenant) { reloaded.verify_backup_code(shown_codes.last) }
      end

      test "backup codes need a second factor first" do
        sign_in_as(@actor)

        post "/account/backup_codes"

        assert_equal flash[:alert], I18n.t("backup_codes.no_second_factor")
        refute reloaded.backup_codes?
      end
    end
  end
end
