module Masks
  module Server
    require "test_helper"

    class EmailCodeTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper

      setup do
        host! host_for(@tenant)
        create_actor(nickname: "owner", email: "owner@example.com")
        @actor = create_actor(nickname: "ada", email: "ada@example.com")
        policy!

        ActionMailer::Base.deliveries.clear
      end

      def policy!(first_factors: %w[password email_code])
        within do
          SignInPolicy.create!(key: "codes", name: "Codes", first_factors: first_factors)
        end.tap { |held| @tenant.update!(sign_in_policy: held) }
      end

      def event(name, **params)
        perform_enqueued_jobs { post "/login", params: { event: name, **params }, as: :json }

        JSON.parse(response.body)
      end

      def mailed_code
        ActionMailer::Base.deliveries.last&.text_part&.body.to_s[/\b\d{6}\b/]
      end

      test "a person signs in with a code sent to their address, and no password" do
        event("identify", identifier: "ada@example.com")

        body = event("email-code:send")

        assert_equal "email-code", body["prompt"]
        assert_equal [ "ada@example.com" ], ActionMailer::Base.deliveries.last.to

        body = event("email-code:verify", code: mailed_code)

        assert body["settled"], body.inspect
        assert_includes within { Session.sole.amr }, "otp"
      end

      test "the code confirms an address that was not confirmed yet" do
        refute @actor.email_verified_at

        event("identify", identifier: "ada")
        event("email-code:send")
        event("email-code:verify", code: mailed_code)

        assert within { @actor.reload.email_verified_at }
      end

      test "an address with no account looks the same and gets no mail" do
        event("identify", identifier: "nobody@example.com")

        body = event("email-code:send")

        assert_equal "email-code", body["prompt"]
        assert_empty ActionMailer::Base.deliveries

        body = event("email-code:verify", code: "123456")

        assert_includes body["warnings"], "invalid-code"
      end

      test "a wrong code is refused, and five wrong codes spend it" do
        event("identify", identifier: "ada@example.com")
        event("email-code:send")
        right = mailed_code
        wrong = right == "000000" ? "111111" : "000000"

        5.times { assert_includes event("email-code:verify", code: wrong)["warnings"], "invalid-code" }

        refute event("email-code:verify", code: right)["settled"]
      end

      test "a code sent to one identifier does not sign in another" do
        event("identify", identifier: "ada@example.com")
        event("email-code:send")
        code = mailed_code

        event("identify", identifier: "owner@example.com")
        body = event("email-code:verify", code: code)

        refute body["settled"]
      end

      test "a code is not sent again within thirty seconds" do
        event("identify", identifier: "ada@example.com")
        event("email-code:send")
        event("email-code:send")

        assert_equal 1, ActionMailer::Base.deliveries.size

        travel(ConfirmationCode::RESEND_AFTER + 1.second) { event("email-code:send") }

        assert_equal 2, ActionMailer::Base.deliveries.size
      end

      test "a code is not offered unless the policy offers it" do
        policy!(first_factors: %w[password])

        event("identify", identifier: "ada@example.com")
        body = event("email-code:send")

        assert_equal "first-factor", body["prompt"]
        assert_empty ActionMailer::Base.deliveries
      end

      test "a code used to sign in cannot also be the email second factor" do
        within do
          @actor.update!(email_verified_at: Time.current)
          CodeFactors.enable!(@actor, "email")
        end

        event("identify", identifier: "ada@example.com")
        event("email-code:send")
        body = event("email-code:verify", code: mailed_code)

        refute_includes body.fetch("codeFactors", {}).keys, "email"
      end
    end
  end
end
