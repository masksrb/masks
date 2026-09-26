module Masks
  module Server
    require "test_helper"

    class CodeFactorsTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper

      CHROME = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
               "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze

      setup do
        host! host_for(@tenant)

        within(@tenant) { Adapters::SmsLog.create!(key: "log", name: "Log", primary: true) }
        policy!

        @actor = create_actor(@tenant, email: "ada@example.com", phone: "+15551234567")
        within(@tenant) { @actor.update!(email_verified_at: Time.current, phone_verified_at: Time.current) }

        ActionMailer::Base.deliveries.clear
        Adapters::SmsLog.deliveries.clear
      end

      def policy!(**attributes)
        within(@tenant) do
          SignInPolicy.create!({ key: "codes", name: "Codes",
                                 second_factors: %w[otp passkey backup_codes email sms] }.merge(attributes))
        end.tap { |held| @tenant.update!(sign_in_policy: held) }
      end

      def event(name, **params)
        perform_enqueued_jobs do
          post "/login", params: { event: name, **params }, as: :json, headers: { "HTTP_USER_AGENT" => CHROME }
        end

        JSON.parse(response.body)
      end

      def turn_on(factor)
        within(@tenant) { CodeFactors.enable!(@actor, factor) }
      end

      def to_second_factor
        event("identify", identifier: @actor.nickname)
        event("password", password: "password")
      end

      def mailed_code
        ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
      end

      def texted_code
        Adapters::SmsLog.deliveries.last[:body][/\b\d{6}\b/]
      end

      def signed_out
        delete "/login"
        cookies.delete(:masks_session)
      end

      def amr
        within(@tenant) { Session.live.where(actor: @actor).order(:created_at).last.amr }
      end

      test "a text message code confirms a sign-in after a password" do
        turn_on("sms")

        body = to_second_factor

        assert_equal "second-factor", body["prompt"]
        assert body.dig("secondFactors", "sms")
        assert_equal "•••• 4567", body.dig("codeFactors", "sms")

        body = event("code:send", factor: "sms")

        assert_equal "sms", body.dig("codeSent", "factor")
        assert_equal "+15551234567", Adapters::SmsLog.deliveries.last[:to]

        assert event("code:verify", code: texted_code)["settled"]
        assert_includes amr, "sms"
        assert_includes amr, "mfa"
      end

      test "an email code confirms a sign-in after a password" do
        with_mailer do
          turn_on("email")

          body = to_second_factor

          assert_equal "a•••@example.com", body.dig("codeFactors", "email")

          event("code:send", factor: "email")

          assert_equal [ "ada@example.com" ], ActionMailer::Base.deliveries.last.to
          assert event("code:verify", code: mailed_code)["settled"]
          assert_includes amr, "mfa"
        end
      end

      test "a wrong code is refused, and a run of them locks the right one out" do
        turn_on("sms")
        to_second_factor
        event("code:send", factor: "sms")

        right = texted_code
        wrong = right == "000000" ? "111111" : "000000"

        body = event("code:verify", code: wrong)

        assert_includes body["warnings"], "invalid-code"
        assert_equal "second-factor", body["prompt"]

        4.times { event("code:verify", code: wrong) }

        refute event("code:verify", code: right)["settled"]
      end

      test "an email code cannot confirm a sign-in that began with a password reset" do
        with_mailer do
          turn_on("email")

          reset = within(@tenant) { PasswordReset.open!(actor: @actor) }
          get "/reset/#{reset.secret}"

          body = event("reset-password", password: "a-new-password-entirely")

          assert_equal "second-factor", body["prompt"]
          assert_nil body["codeFactors"]&.dig("email")
          assert_equal [ "email" ], body["codesWithheld"]

          body = event("code:send", factor: "email")

          assert_includes body["warnings"], "factor-not-offered"
          assert_empty ActionMailer::Base.deliveries.select { |mail| mail.to == [ "ada@example.com" ] &&
                                                                     mail.subject.to_s.match?(/\d{6}/) }
        end
      end

      test "a text message code still confirms a sign-in that began with a password reset" do
        turn_on("sms")

        reset = within(@tenant) { PasswordReset.open!(actor: @actor) }
        get "/reset/#{reset.secret}"
        event("reset-password", password: "a-new-password-entirely")

        event("code:send", factor: "sms")

        assert event("code:verify", code: texted_code)["settled"]
      end

      test "a policy that stops offering a factor stops asking for it" do
        turn_on("sms")
        policy!(key: "plain", name: "Plain", second_factors: %w[otp passkey backup_codes])

        assert to_second_factor["settled"]
      end

      test "a new phone number or email address turns its codes off" do
        turn_on("sms")
        turn_on("email")

        within(@tenant) do
          @actor.reload.update!(phone: "+15557654321", phone_verified_at: Time.current)
          refute @actor.reload.phone_factor?
          assert @actor.email_factor?

          @actor.update!(email: "lovelace@example.com")
          refute @actor.reload.email_factor?
        end
      end

      test "a code does not travel to a sign-in that did not ask for it" do
        turn_on("sms")
        to_second_factor
        event("code:send", factor: "sms")
        code = texted_code

        reset!
        host! host_for(@tenant)
        to_second_factor

        body = event("code:verify", code: code)

        assert_includes body["warnings"], "confirmation-expired"
      end

      test "the tick trusts the device after a text message code" do
        turn_on("sms")
        to_second_factor
        event("code:send", factor: "sms")

        assert event("code:verify", code: texted_code, remember: true)["settled"]

        signed_out

        assert to_second_factor["settled"]
      end

      test "a policy requiring a second factor is satisfied by a text message code turned on at enrolment" do
        policy!(key: "strict", name: "Strict", second_factor_required: true)

        body = to_second_factor

        assert_equal "enrol", body["prompt"]
        assert body.dig("enrolment", "offers", "sms")
        assert_equal "+15551234567", body.dig("enrolment", "codes", "sms", "to")

        body = event("enrol:code-send", factor: "sms")

        assert body.dig("enrolment", "codes", "sms", "sent")

        body = event("enrol:code", code: texted_code)

        assert body.dig("enrolment", "codes", "sms", "enabled")
        refute body.dig("enrolment", "required")

        event("enrol:done", kept: "1")

        within(@tenant) { assert @actor.reload.phone_factor? }
      end

      test "a manager still needs an authenticator app or a passkey after turning on codes" do
        manager = create_actor(@tenant, nickname: "boss", scopes: "openid masks:manage", otp: false,
                                        phone: "+15550001111")
        within(@tenant) { manager.update!(phone_verified_at: Time.current) }

        event("identify", identifier: "boss")
        event("password", password: "password")
        event("enrol:code-send", factor: "sms")

        body = event("enrol:code", code: texted_code)

        assert body.dig("enrolment", "codes", "sms", "enabled")
        assert body.dig("enrolment", "required")

        body = event("enrol:done", kept: "1")

        assert_includes body["warnings"], "second-factor-required"
        assert_nil within(@tenant) { Session.live.find_by(actor_id: manager.id) }
      end

      test "the account page turns codes on and off, and records both" do
        sign_in_as(@actor)

        get root_path
        assert_select "#sms-codes .entry-state", text: "Off"

        post account_code_factor_path("sms")
        assert_redirected_to root_path
        within(@tenant) { assert @actor.reload.phone_factor? }

        delete account_code_factor_path("sms")
        within(@tenant) do
          refute @actor.reload.phone_factor?
          assert Event.exists?(actor: @actor, action: Event::TEXT_CODES_ENABLED)
          assert Event.exists?(actor: @actor, action: Event::TEXT_CODES_DISABLED)
        end
      end

      test "the account page will not turn on codes for an unconfirmed address" do
        within(@tenant) { @actor.update!(phone_verified_at: nil) }
        sign_in_as(@actor)

        post account_code_factor_path("sms")

        assert_equal I18n.t("code_factors.unconfirmed"), flash[:alert]
        within(@tenant) { refute @actor.reload.phone_factor_at }
      end

      test "the account page will not turn on a factor the policy does not offer" do
        policy!(key: "plain", name: "Plain", second_factors: %w[otp passkey backup_codes])
        sign_in_as(@actor)

        post account_code_factor_path("email")

        assert_equal I18n.t("code_factors.unoffered"), flash[:alert]
      end

      test "without javascript a text message code is sent and checked through plain forms" do
        turn_on("sms")

        post "/login", params: { event: "identify", identifier: @actor.nickname }
        post "/login", params: { event: "password", password: "password" }
        follow_redirect! while response.redirect?

        assert_select "form#send-sms-code"
        assert_select "form#second-factor", count: 0

        perform_enqueued_jobs { post "/login", params: { event: "code:send", factor: "sms" } }
        follow_redirect! while response.redirect?

        assert_select "form#second-factor input[name=event][value='code:verify']"

        post "/login", params: { event: "code:verify", code: texted_code }

        within(@tenant) { assert Session.live.exists?(actor: @actor) }
      end

      test "a manager turns someone's codes off through the manage API" do
        turn_on("sms")

        manager = create_actor(@tenant, nickname: "boss", scopes: "openid masks:manage")
        client = create_client(@tenant, allowed_scopes: "openid masks:manage", approved_at: Time.current,
                                        grant_types: [ "authorization_code" ])

        sign_in_as(manager)
        authorize(client_id: client.client_id, scope: "openid masks:manage",
                  resource: issuer_for(@tenant).manage_resource)
        consent! if awaiting_consent?

        bearer = token(grant_type: "authorization_code", code: code_from, redirect_uri: OidcFlow::REDIRECT_URI,
                       code_verifier: verifier, client_id: client.client_id)["access_token"]

        post "/manage/graphql",
             params: { query: "mutation($uuid: ID!) { disableCodeFactor(uuid: $uuid, factor: \"sms\") " \
                              "{ actor { textCodesEnabled } } }",
                       variables: { uuid: @actor.uuid } }.to_json,
             headers: { "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer #{bearer}" }

        assert_equal false, JSON.parse(response.body).dig("data", "disableCodeFactor", "actor", "textCodesEnabled")

        within(@tenant) do
          refute @actor.reload.phone_factor?
          assert_equal manager.id, Event.where(action: Event::TEXT_CODES_DISABLED).last.by_id
        end
      end
    end
  end
end
