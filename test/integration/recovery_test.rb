module Masks
  module Server
    require "test_helper"

    class RecoveryTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper

      setup do
        host! host_for(@tenant)

        @owner = create_actor(@tenant, nickname: "owner", scopes: "openid profile email masks:manage")
        within(@tenant) { @owner.update!(email_verified_at: Time.current) }

        @actor = create_actor(@tenant, nickname: "ada", email: "ada@example.com", otp: true)
        within(@tenant) { @actor.update!(email_verified_at: Time.current) }

        @client = create_client(
          @tenant,
          allowed_scopes: "openid profile email masks:manage",
          approved_at: Time.current,
          grant_types: [ "authorization_code", "refresh_token" ]
        )

        ActionMailer::Base.deliveries.clear
      end

      def event(name, **params)
        perform_enqueued_jobs { post "/login", params: { event: name, **params }, as: :json }

        JSON.parse(response.body)
      end

      def to_second_factor
        event("identify", identifier: "ada")
        event("password", password: "password")
      end

      def bearer
        reset!
        host! host_for(@tenant)
        sign_in_as(@owner)
        authorize(client_id: @client.client_id, scope: "openid masks:manage", resource: issuer_for(@tenant).manage_resource)
        consent! if awaiting_consent?

        token(grant_type: "authorization_code", code: code_from, redirect_uri: OidcFlow::REDIRECT_URI,
              code_verifier: verifier, client_id: @client.client_id)["access_token"]
      end

      def ask(query, token, **variables)
        perform_enqueued_jobs do
          post "/manage/graphql",
               params: { query: query, variables: variables }.to_json,
               headers: { "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer #{token}" }
        end

        JSON.parse(response.body)
      end

      def reloaded
        within(@tenant) { @actor.reload }
      end

      test "someone past their password asks for help, and the managers and the account hear about it" do
        with_mailer do
          body = to_second_factor

          assert_equal "second-factor", body["prompt"]
          refute body.dig("recovery", "requested")

          body = event("recovery:request")

          assert body.dig("recovery", "requested")
          assert reloaded.recovery_requested_at.present?
          assert_includes ActionMailer::Base.deliveries.map(&:to), [ "owner@example.invalid" ]
          assert_includes ActionMailer::Base.deliveries.map(&:to), [ "ada@example.com" ]
          assert within(@tenant) { Event.where(action: Event::RECOVERY_REQUESTED, actor: @actor).exists? }
        end
      end

      test "asking again the same day mails nobody twice" do
        with_mailer do
          to_second_factor
          event("recovery:request")
          sent = ActionMailer::Base.deliveries.size

          event("recovery:request")

          assert_equal sent, ActionMailer::Base.deliveries.size
        end
      end

      test "help cannot be asked for before the first factor" do
        event("identify", identifier: "ada")
        event("recovery:request")

        assert_nil reloaded.recovery_requested_at
      end

      test "a manager finds the request and resets every second factor" do
        to_second_factor
        event("recovery:request")

        token = bearer
        listed = ask("{ actors(recoveryRequested: true) { identifier } }", token)

        assert_equal [ "ada" ], listed.dig("data", "actors").map { |actor| actor["identifier"] }

        answer = ask(<<~GQL, token, uuid: @actor.uuid)
          mutation Reset($uuid: ID!) { resetSecondFactors(uuid: $uuid) { actor { otpEnabled recoveryRequestedAt } } }
        GQL

        assert_nil answer["errors"]
        refute answer.dig("data", "resetSecondFactors", "actor", "otpEnabled")
        assert_nil reloaded.recovery_requested_at
        refute reloaded.second_factor?
        assert within(@tenant) { Event.where(action: Event::SECOND_FACTORS_RESET, actor: @actor, by: @owner).exists? }

        reset!
        host! host_for(@tenant)

        refute_equal "second-factor", to_second_factor["prompt"]
      end

      test "a manager can dismiss a request" do
        to_second_factor
        event("recovery:request")

        answer = ask(<<~GQL, bearer, uuid: @actor.uuid)
          mutation Dismiss($uuid: ID!) { dismissRecovery(uuid: $uuid) { actor { recoveryRequestedAt } } }
        GQL

        assert_nil answer["errors"]
        assert_nil reloaded.recovery_requested_at
        assert reloaded.otp?
      end
    end
  end
end
