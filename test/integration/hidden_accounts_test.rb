module Masks
  module Server
    require "test_helper"

    class HiddenAccountsTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper

      PASSWORD = "a-long-enough-password".freeze
      CHROME = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
               "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze

      setup do
        host! host_for(@tenant)

        @owner = create_actor(@tenant, nickname: "owner", email: "owner@example.com", otp: false)
        ActionMailer::Base.deliveries.clear
      end

      def policy!(**attributes)
        within(@tenant) do
          SignInPolicy.create!({ key: "hidden", name: "Hidden", signup: true, hidden: true,
                                 second_factors: [ "backup_codes" ] }.merge(attributes))
        end.tap { |held| @tenant.update!(sign_in_policy: held) }
      end

      def event(name, **params)
        perform_enqueued_jobs do
          post "/login", params: { event: name, **params }, as: :json, headers: { "HTTP_USER_AGENT" => CHROME }
        end

        JSON.parse(response.body)
      end

      def mailed_code(to)
        mail = ActionMailer::Base.deliveries.reverse.find { |sent| sent.to == [ to ] }

        mail&.text_part&.body.to_s[/\b\d{6}\b/]
      end

      def fresh!
        reset!
        host! host_for(@tenant)
      end

      def created
        within(@tenant) { Actor.find_by(email: "ada@example.com") }
      end

      test "an address with an account and one without are answered the same way" do
        with_mailer do
          policy!

          known = event("identify", identifier: "owner@example.com")
          fresh!
          unknown = event("identify", identifier: "ada@example.com")

          assert_equal "prove-email", known["prompt"]
          assert_equal known["prompt"], unknown["prompt"]
          assert_equal known.keys.sort, unknown.keys.sort
          assert_nil known["journey"]
          assert_nil unknown["journey"]
          assert mailed_code("owner@example.com")
          assert mailed_code("ada@example.com")
        end
      end

      test "a proven address with an account goes on to its password, and the address is confirmed" do
        with_mailer do
          policy!

          event("identify", identifier: "owner@example.com")

          assert_equal "first-factor", event("inbox:verify", code: mailed_code("owner@example.com"))["prompt"]
          assert event("password", password: "password")["settled"]
          assert within(@tenant) { @owner.reload.email_verified_at }
        end
      end

      test "a proven address with no account goes on to signup, and keeps that address" do
        with_mailer do
          policy!(confirmation: "code")

          event("identify", identifier: "ada@example.com")
          body = event("inbox:verify", code: mailed_code("ada@example.com"))

          assert_equal "signup", body["prompt"]
          assert_equal [ "email" ], body.dig("signup", "fixed")

          event("signup", nickname: "ada", email: "mallory@example.com")
          body = event("signup", password: PASSWORD, password_confirmation: PASSWORD)

          assert body["settled"], body["prompt"]
          assert_equal "ada@example.com", created.email
          assert created.email_verified_at
        end
      end

      test "proving an address confirms nobody's account until that account signs in" do
        with_mailer do
          policy!

          event("identify", identifier: "owner@example.com")
          event("inbox:verify", code: mailed_code("owner@example.com"))

          assert_nil within(@tenant) { @owner.reload.email_verified_at }

          event("password", password: "password")

          assert within(@tenant) { @owner.reload.email_verified_at }
        end
      end

      test "somebody signed in to one account still proves the address of another" do
        with_mailer do
          policy!
          other = create_actor(@tenant, nickname: "other", email: "other@example.com", otp: false)

          event("identify", identifier: "owner@example.com")
          event("inbox:verify", code: mailed_code("owner@example.com"))
          assert event("password", password: "password")["settled"]

          body = event("identify", identifier: other.email)

          assert_equal "prove-email", body["prompt"]
          assert_includes event("password", password: "password")["warnings"], "prove-email-first"
        end
      end

      test "no password is checked before the address is proven" do
        with_mailer do
          policy!

          event("identify", identifier: "owner@example.com")
          body = event("password", password: "password")

          assert_includes body["warnings"], "prove-email-first"
          assert_equal "prove-email", body["prompt"]
        end
      end

      test "signup is not reached by skipping the proof" do
        with_mailer do
          policy!

          event("identify", identifier: "ada@example.com")
          event("signup", nickname: "ada", email: "ada@example.com")
          event("signup", password: PASSWORD, password_confirmation: PASSWORD)

          assert_nil created
        end
      end

      test "an unknown nickname is not offered signup, so it cannot tell which nicknames exist" do
        with_mailer do
          policy!

          assert_equal "first-factor", event("identify", identifier: "ada")["prompt"]
          fresh!
          assert_equal "first-factor", event("identify", identifier: "owner")["prompt"]
        end
      end

      test "a wrong code is refused, and says nothing about the account" do
        with_mailer do
          policy!

          event("identify", identifier: "owner@example.com")
          body = event("inbox:verify", code: "000000")

          assert_includes body["warnings"], "invalid-code"
          assert_equal "prove-email", body["prompt"]
        end
      end

      test "with signup closed, a proven address with no account is told so" do
        with_mailer do
          policy!(signup: false)

          event("identify", identifier: "ada@example.com")
          body = event("inbox:verify", code: mailed_code("ada@example.com"))

          assert_includes body["warnings"], "no-account-for-email"
          assert_equal "identify", body["prompt"]
        end
      end

      test "a device the account has signed in on before skips the code" do
        with_mailer do
          policy!

          event("identify", identifier: "owner@example.com")
          event("inbox:verify", code: mailed_code("owner@example.com"))
          event("password", password: "password")
          within(@tenant) { DeviceFactor.remember!(device: Device.last, actor: @owner) }

          delete "/login", headers: { "HTTP_USER_AGENT" => CHROME }
          cookies.delete(:masks_session)
          ActionMailer::Base.deliveries.clear

          assert_equal "first-factor", event("identify", identifier: "owner@example.com")["prompt"]
          assert_empty ActionMailer::Base.deliveries
        end
      end

      test "an address is sent only so many codes" do
        with_mailer do
          policy!

          ::Rails.configuration.masks.recovery_limit.times do
            event("identify", identifier: "ada@example.com")
            fresh!
          end

          body = event("identify", identifier: "ada@example.com")

          assert_includes body["warnings"], "too-many-codes"
          assert_equal ::Rails.configuration.masks.recovery_limit, ActionMailer::Base.deliveries.size
        end
      end

      test "a code proves only the address it was sent to" do
        with_mailer do
          policy!

          event("identify", identifier: "ada@example.com")
          code = mailed_code("ada@example.com")

          event("start-over")
          event("identify", identifier: "owner@example.com")
          body = event("inbox:verify", code: code)

          assert_equal "prove-email", body["prompt"]
          assert_includes body["warnings"], "invalid-code"
        end
      end

      test "a policy that does not hide goes straight to signup, as before" do
        policy!(hidden: false)

        assert_equal "signup", event("identify", identifier: "ada@example.com")["prompt"]
      end
    end
  end
end
