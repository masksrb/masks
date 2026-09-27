module Masks
  module Server
    require "test_helper"

    class RiskTest < ActionDispatch::IntegrationTest
      setup do
        host! host_for(@tenant)
        @actor = create_actor(email: "ada@probe.example.com")
      end

      def policy(**attributes)
        within do
          SignInPolicy.create!(key: "risky", name: "Risky", **attributes).tap { |held| @tenant.update!(sign_in_policy: held) }
        end
      end

      def seen_before(ip_address: "198.51.100.7")
        within { Session.start!(actor: @actor, ip_address: ip_address).revoke! }
      end

      def with_breaches(answer)
        held = BreachedPasswords.method(:breached?)
        BreachedPasswords.define_singleton_method(:breached?) { |_password| answer }

        yield
      ensure
        BreachedPasswords.define_singleton_method(:breached?, held)
      end

      def password_step
        post "/login", params: { event: "identify", identifier: @actor.nickname }, as: :json
        post "/login", params: { event: "password", password: "password" }, as: :json

        JSON.parse(response.body)
      end

      test "a first sign-in scores nothing, so nothing more is asked" do
        policy(risk_step_up_at: 30, risk_refuse_at: 90)

        body = password_step

        assert body["settled"], body.inspect
        refute within { Event.exists?(action: Event::SIGN_IN_RISKY) }
      end

      test "a sign-in from a new device on a new network is asked for a second factor" do
        policy(risk_step_up_at: 50)
        enable_otp(@actor)
        seen_before

        body = password_step

        assert_equal "second-factor", body["prompt"]

        event = within { Event.where(action: Event::SIGN_IN_RISKY).sole }

        assert_equal 55, event.details["score"]
        assert_equal %w[new_device new_network], event.details["signals"]
        assert event.details["stepped_up"]
      end

      test "an account with no second factor is asked to add one when risk asks for it" do
        policy(risk_step_up_at: 50)
        seen_before

        assert_equal "enrol", password_step["prompt"]
      end

      test "a sign-in scoring past the refusal line is refused and the person is told" do
        policy(risk_refuse_at: 50)
        seen_before

        body = password_step

        assert_includes body["warnings"], "risky-sign-in"
        refute body["settled"]
        assert within { Event.where(action: Event::LOGIN_REFUSED).any? { |held| held.details["factor"] == "risk" } }
      end

      test "a network the tenant lists as risky adds to the score" do
        within { @tenant.update!(risky_networks: "127.0.0.0/8") }
        policy(risk_refuse_at: 50)
        seen_before(ip_address: "127.0.0.1")

        assert_includes password_step["warnings"], "risky-sign-in"
      end

      test "a breached password adds to the score when the policy checks for breaches" do
        policy(refuse_breached_passwords: true, risk_refuse_at: 40)

        body = with_breaches(true) { password_step }

        assert_includes body["warnings"], "risky-sign-in"
      end

      test "a breached password is refused as a new password" do
        policy(refuse_breached_passwords: true)
        sign_in_as(@actor)

        with_breaches(true) do
          patch "/account/password", params: { current_password: "password", password: "correct horse battery staple" }
        end

        assert_equal "That password has appeared in a data breach. Choose another.", flash[:password_field]["password"]
      end

      test "the refusal line must sit above the second-factor line" do
        held = within { SignInPolicy.new(key: "x", name: "X", risk_step_up_at: 70, risk_refuse_at: 50) }

        refute within { held.valid? }
      end
    end
  end
end
