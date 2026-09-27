module Masks
  module Server
    require "test_helper"

    class StepUpTest < ActionDispatch::IntegrationTest
      MFA = Issuer::ACR_MULTI_FACTOR

      setup do
        @registration = register
        host! host_for(@tenant)
      end

      def acr_of(body)
        claims_in(body["id_token"])["acr"]
      end

      test "a session that used a second factor satisfies a request for one without asking again" do
        actor = create_actor(email: "owner@probe.example.com")
        enable_otp(actor)

        sign_in_as(actor)
        authorize(client_id: @registration["client_id"], acr_values: MFA)
        consent! if awaiting_consent?

        assert code_from.present?

        body = token(grant_type: "authorization_code", code: code_from, redirect_uri: OidcFlow::REDIRECT_URI,
                     code_verifier: verifier, client_id: @registration["client_id"],
                     client_secret: @registration["client_secret"])

        assert_equal MFA, acr_of(body)
      end

      test "a session that used only a password is asked for the second factor an account holds" do
        actor = create_actor(email: "owner@probe.example.com")

        sign_in_as(actor)
        enable_otp(actor)

        authorize(client_id: @registration["client_id"], acr_values: MFA)

        assert awaiting_login?
        assert_equal "second-factor", auth_data["prompt"]
      end

      test "an account with no second factor is asked to add one when a request wants one" do
        actor = create_actor(email: "owner@probe.example.com")

        sign_in_as(actor)
        authorize(client_id: @registration["client_id"], acr_values: MFA)

        assert awaiting_login?
        assert_equal "enrol", auth_data["prompt"]
      end

      test "a request that does not ask for a second factor is not asked for one" do
        actor = create_actor(email: "owner@probe.example.com")

        sign_in_as(actor)
        authorize(client_id: @registration["client_id"])
        consent! if awaiting_consent?

        assert code_from.present?
      end

      test "the claims parameter can ask for a second factor too" do
        actor = create_actor(email: "owner@probe.example.com")

        sign_in_as(actor)
        authorize(client_id: @registration["client_id"],
                  claims: { id_token: { acr: { essential: true, values: [ MFA ] } } }.to_json)

        assert awaiting_login?
        assert_equal "enrol", auth_data["prompt"]
      end

      test "a policy that asks at every app sign-in steps up a session that used only a password" do
        actor = create_actor(email: "owner@probe.example.com")

        sign_in_as(actor)
        enable_otp(actor)

        within do
          policy = SignInPolicy.create!(key: "apps", name: "Apps", apps_require_second_factor: true)
          Client.find_by!(client_id: @registration["client_id"]).update!(sign_in_policy: policy)
        end

        authorize(client_id: @registration["client_id"])

        assert awaiting_login?
        assert_equal "second-factor", auth_data["prompt"]
      end

      test "a policy that asks at every app sign-in lets a session that used a second factor through" do
        actor = create_actor(email: "owner@probe.example.com")
        enable_otp(actor)

        within do
          policy = SignInPolicy.create!(key: "apps", name: "Apps", apps_require_second_factor: true)
          Client.find_by!(client_id: @registration["client_id"]).update!(sign_in_policy: policy)
        end

        sign_in_as(actor)
        authorize(client_id: @registration["client_id"])
        consent! if awaiting_consent?

        assert code_from.present?
      end

      test "a policy cannot ask at every app sign-in when it offers only backup codes" do
        policy = within do
          SignInPolicy.new(key: "apps", name: "Apps", apps_require_second_factor: true, second_factors: [ "backup_codes" ])
        end

        refute within { policy.valid? }
        assert_includes policy.errors[:second_factors], "must offer more than backup codes when one is required"
      end

      test "an unrelated acr value asks for nothing more" do
        actor = create_actor(email: "owner@probe.example.com")

        sign_in_as(actor)
        authorize(client_id: @registration["client_id"], acr_values: Issuer::ACR_PASSWORD)
        consent! if awaiting_consent?

        assert code_from.present?
      end
    end
  end
end
