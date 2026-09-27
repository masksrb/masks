module Masks
  module Server
    require "test_helper"

    class EmailCodeTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper

      setup do
        host! host_for(@tenant)
        create_actor(nickname: "owner", email: "owner@example.com")
        @actor = create_actor(nickname: "ada", email: "ada@example.com")
        within { @actor.update!(email_verified_at: Time.current) }
        policy!

        ActionMailer::Base.deliveries.clear
      end

      def policy!(first_factors: %w[password email_code])
        within do
          SignInPolicy.find_or_initialize_by(key: "codes").tap do |held|
            held.update!(name: "Codes", first_factors: first_factors)
          end
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

      test "the code confirms the address of an account with no password" do
        grace = within { Actor.create!(nickname: "grace", email: "grace@example.com", activated_at: Time.current) }

        event("identify", identifier: "grace")
        event("email-code:send")
        event("email-code:verify", code: mailed_code)

        assert within { grace.reload.email_verified_at }
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
        within { CodeFactors.enable!(@actor, "email") }

        event("identify", identifier: "ada@example.com")
        event("email-code:send")
        body = event("email-code:verify", code: mailed_code)

        refute_includes body.fetch("codeFactors", {}).keys, "email"
      end

      test "an account with a password and an unconfirmed address gets no code, so a code cannot confirm someone else's sign-up" do
        within { @actor.update!(email_verified_at: nil) }
        assert @actor.password?

        event("identify", identifier: "ada@example.com")
        event("email-code:send")

        assert_empty ActionMailer::Base.deliveries
      end

      test "too many codes for one account looks the same as an address with no account" do
        ::Rails.configuration.masks.recovery_limit.times do |sent|
          travel((ConfirmationCode::RESEND_AFTER + 1.second) * sent) do
            event("identify", identifier: "ada@example.com")
            event("email-code:send")
          end
        end

        travel((ConfirmationCode::RESEND_AFTER + 1.second) * ::Rails.configuration.masks.recovery_limit) do
          body = event("email-code:send")

          assert_equal "email-code", body["prompt"]
          refute_includes Array(body["warnings"]), "too-many-codes"
        end
      end
    end
  end
end
