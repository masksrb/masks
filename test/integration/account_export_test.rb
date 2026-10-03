module Masks
  module Server
    require "test_helper"

    class AccountExportTest < ActionDispatch::IntegrationTest
      setup do
        host! host_for(@tenant)

        @actor = create_actor(@tenant, nickname: "keeper", email: "keeper@example.com", name: "Kim Keeper",
                                       given_name: "Kim", birthdate: "1990-04-01")
      end

      def downloaded
        assert_response :success
        JSON.parse(response.body)
      end

      test "a person downloads what masks holds about them as a JSON file" do
        sign_in_as(@actor)

        post "/account/export"

        assert_equal "application/json", response.media_type
        assert_match(/attachment; filename="#{@tenant.subdomain}-keeper-\d{4}-\d{2}-\d{2}\.json"/,
                     response.headers["Content-Disposition"])
        assert_equal "no-store", response.headers["Cache-Control"]

        body = downloaded
        assert_equal @actor.uuid, body.dig("account", "uuid")
        assert_equal "keeper@example.com", body.dig("account", "email")
        assert_equal "1990-04-01", body.dig("account", "birthdate")
        assert_equal true, body.dig("factors", "password")
        assert_includes body["events"].map { |event| event["action"] }, Event::SESSION_STARTED
        assert_predicate body["devices"], :any?
      end

      test "the file holds no secret a sign-in depends on" do
        enable_otp(@actor, @tenant)
        within { @actor.reload }
        sign_in_as(@actor)

        post "/account/export"
        raw = response.body

        within do
          held = Actor.find(@actor.id)
          assert_not_includes raw, held.password_digest
          assert_not_includes raw, held.otp_secret
        end
        %w[password_digest otp_secret backup_code_digests webauthn_id public_key access_token refresh_token].each do |field|
          assert_not_includes raw, "\"#{field}\"", field
        end
        assert downloaded.dig("factors", "authenticator_app").present?
      end

      test "each download is recorded" do
        sign_in_as(@actor)

        post "/account/export"

        within { assert Event.exists?(action: Event::ACCOUNT_EXPORTED, actor: @actor) }
      end

      test "it holds only this person's events" do
        other = create_actor(@tenant, nickname: "other")
        within { Event.record!(Event::PASSWORD_CHANGED, actor: other, by: nil) }
        sign_in_as(@actor)

        post "/account/export"

        assert downloaded["events"].all? { |event| event["actor"] == @actor.uuid }
      end

      test "a sign-in older than fifteen minutes is asked to sign in again first" do
        sign_in_as(@actor)

        travel 16.minutes do
          post "/account/export"

          assert_redirected_to login_path(return_to: "#{root_path}#export")
          within { assert_not Event.exists?(action: Event::ACCOUNT_EXPORTED) }
        end
      end

      test "nobody signed in is sent to sign in" do
        post "/account/export"

        assert_redirected_to login_path
      end

      test "the account page offers the download" do
        sign_in_as(@actor)

        get "/"

        assert_select "form#export-account[action=\"/account/export\"][method=\"post\"]"
      end
    end
  end
end
