module Masks
  module Server
    require "test_helper"

    class SignInApprovalTest < ActionDispatch::IntegrationTest
      CHROME = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
               "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze
      FIREFOX = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0".freeze

      setup do
        host! host_for(@tenant)

        within(@tenant) do
          SignInPolicy.create!(key: "approvals", name: "Approvals",
                               second_factors: %w[otp passkey backup_codes trusted_device])
        end.tap { |held| @tenant.update!(sign_in_policy: held) }

        @actor = create_actor(@tenant)
        @totp = enable_otp(@actor)
      end

      def browser(agent)
        open_session do |held|
          held.host! host_for(@tenant)
          held.define_singleton_method(:agent) { agent }
        end
      end

      def event(on, name, **params)
        on.post "/login", params: { event: name, **params }, as: :json, headers: { "HTTP_USER_AGENT" => on.agent }

        JSON.parse(on.response.body)
      end

      def to_second_factor(on)
        event(on, "identify", identifier: @actor.nickname)
        event(on, "password", password: "password")
      end

      def trusted_browser
        browser(CHROME).tap do |held|
          to_second_factor(held)
          assert event(held, "otp", code: @totp.now, remember: true)["settled"]
        end
      end

      def approve_on(held, code, answer: "approve")
        headers = { "HTTP_USER_AGENT" => held.agent }

        held.post "/account/approve", params: { code: code }, headers: headers
        held.patch "/account/approve", params: { answer: answer }, headers: headers
      end

      test "a trusted device approves a sign-in from a code the other screen shows" do
        trusted = trusted_browser
        asking = browser(FIREFOX)

        body = to_second_factor(asking)

        assert body.dig("secondFactors", "trustedDevice")

        body = event(asking, "approval:request")
        code = body.dig("approval", "code")

        assert_match(/\A\d{6}\z/, code)
        refute event(asking, "approval:check")["settled"]

        trusted.get "/", headers: { "HTTP_USER_AGENT" => CHROME }
        trusted.assert_select "#approve-sign-in"

        trusted.post "/account/approve", params: { code: code }, headers: { "HTTP_USER_AGENT" => CHROME }
        trusted.follow_redirect!
        trusted.assert_select "#approve .item-name", text: "Firefox on Windows"

        trusted.patch "/account/approve", params: { answer: "approve" }, headers: { "HTTP_USER_AGENT" => CHROME }

        assert event(asking, "approval:check")["settled"]

        within(@tenant) do
          assert_includes Session.live.where(actor: @actor).order(:created_at).last.amr, "mfa"
          assert Event.exists?(actor: @actor, action: Event::SIGN_IN_APPROVED)
        end
      end

      test "a denied sign-in says so and goes no further" do
        trusted = trusted_browser
        asking = browser(FIREFOX)

        to_second_factor(asking)
        code = event(asking, "approval:request").dig("approval", "code")

        approve_on(trusted, code, answer: "deny")

        body = event(asking, "approval:check")

        refute body["settled"]
        assert_includes body["warnings"], "approval-denied"
        assert body.dig("approval", "denied")
      end

      test "an approval is claimed once, by the sign-in that asked for it" do
        trusted = trusted_browser
        asking = browser(FIREFOX)
        other = browser(FIREFOX)

        to_second_factor(asking)
        to_second_factor(other)
        code = event(asking, "approval:request").dig("approval", "code")

        approve_on(trusted, code)

        refute event(other, "approval:check")["settled"]
        assert event(asking, "approval:check")["settled"]
      end

      test "a signed-in device that was never trusted cannot approve" do
        untrusted = browser(CHROME)
        to_second_factor(untrusted)
        assert event(untrusted, "otp", code: @totp.now)["settled"]

        asking = browser(FIREFOX)
        to_second_factor(asking)
        code = event(asking, "approval:request").dig("approval", "code")

        untrusted.get "/", headers: { "HTTP_USER_AGENT" => CHROME }
        untrusted.assert_select "#approve-sign-in", count: 0

        approve_on(untrusted, code)

        assert_equal I18n.t("sign_in_approvals.untrusted"), untrusted.flash[:alert]
        refute event(asking, "approval:check")["settled"]
      end

      test "a wrong code finds nothing to approve" do
        trusted = trusted_browser
        asking = browser(FIREFOX)

        to_second_factor(asking)
        code = event(asking, "approval:request").dig("approval", "code")
        wrong = code == "000000" ? "111111" : "000000"

        trusted.post "/account/approve", params: { code: wrong }, headers: { "HTTP_USER_AGENT" => CHROME }

        assert_equal I18n.t("sign_in_approvals.no_match"), trusted.flash[:alert]

        trusted.patch "/account/approve", params: { answer: "approve" }, headers: { "HTTP_USER_AGENT" => CHROME }

        refute event(asking, "approval:check")["settled"]
      end

      test "a code for someone else's sign-in finds nothing" do
        trusted = trusted_browser

        stranger = create_actor(@tenant, nickname: "stranger")
        stranger_totp = enable_otp(stranger)
        other = browser(CHROME)
        event(other, "identify", identifier: "stranger")
        event(other, "password", password: "password")
        event(other, "otp", code: stranger_totp.now, remember: true)

        asking = browser(FIREFOX)
        event(asking, "identify", identifier: "stranger")
        event(asking, "password", password: "password")
        code = event(asking, "approval:request").dig("approval", "code")

        trusted.post "/account/approve", params: { code: code }, headers: { "HTTP_USER_AGENT" => CHROME }

        assert_equal I18n.t("sign_in_approvals.no_match"), trusted.flash[:alert]
      end

      test "a policy that does not offer it neither shows it nor opens one" do
        trusted_browser

        within(@tenant) do
          SignInPolicy.create!(key: "plain", name: "Plain", second_factors: %w[otp passkey backup_codes])
        end.tap { |held| @tenant.update!(sign_in_policy: held) }

        asking = browser(FIREFOX)
        body = to_second_factor(asking)

        refute body.dig("secondFactors", "trustedDevice")
        assert_nil event(asking, "approval:request")["approval"]
        assert_equal 0, within(@tenant) { SignInApproval.count }
      end

      test "the tick trusts the approved device too" do
        trusted = trusted_browser
        asking = browser(FIREFOX)

        to_second_factor(asking)
        code = event(asking, "approval:request").dig("approval", "code")
        approve_on(trusted, code)

        assert event(asking, "approval:check", remember: true)["settled"]

        asking.delete "/login"
        asking.cookies.delete(:masks_session)

        assert to_second_factor(asking)["settled"]
      end
    end
  end
end
