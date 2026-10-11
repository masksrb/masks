module Masks
  module Server
    require "test_helper"
    require_relative "../support/solves_work"

    class SignupWorkTest < ActionDispatch::IntegrationTest
      include SolvesWork

      PASSWORD = "a-long-enough-password".freeze
      DETAILS = { nickname: "ada", email: "ada@example.com" }.freeze

      setup do
        host! host_for(@tenant)

        create_actor(@tenant, nickname: "owner", scopes: "openid masks:manage")
      end

      def policy!(**attributes)
        within(@tenant) do
          SignInPolicy.create!({ key: "open", name: "Open", signup: true, second_factors: [ "backup_codes" ],
                                 proof_of_work: 8 }.merge(attributes))
        end.tap { |held| @tenant.update!(sign_in_policy: held) }
      end

      def event(name, **params)
        post "/login", params: { event: name, **params }, as: :json

        JSON.parse(response.body)
      end

      def created
        within(@tenant) { Actor.find_by(nickname: "ada") }
      end

      test "an open signup hands the browser a challenge, and an account follows a solved one" do
        policy!

        body = event("identify", identifier: "ada@example.com")
        work = body.dig("signup", "work")

        assert_equal "signup", body["prompt"]
        assert_equal 8, work["bits"]
        assert work["nonce"].present?

        body = event("signup", **DETAILS, **solve_work(work))

        assert_equal "signup-credentials", body["prompt"]
        assert_nil body.dig("signup", "work")

        body = event("signup", password: PASSWORD, password_confirmation: PASSWORD)

        assert body["settled"], body["prompt"]
        assert created
      end

      test "details sent without a solved challenge are held back" do
        policy!

        work = event("identify", identifier: "ada@example.com").dig("signup", "work")

        body = event("signup", **DETAILS)

        assert_equal "signup", body["prompt"]
        assert_includes body["warnings"], "work-unsolved"

        wrong = (0..).find { |held| !ProofOfWork.solves?(work["nonce"], held, work["bits"]) }
        body = event("signup", **DETAILS, work: work["token"], work_counter: wrong.to_s)

        assert_includes body["warnings"], "work-unsolved"
        assert_nil event("signup", password: PASSWORD, password_confirmation: PASSWORD)["settled"].presence
        assert_nil created
      end

      test "a challenge solved for one sign-in cannot be spent on another" do
        policy!

        work = event("identify", identifier: "ada@example.com").dig("signup", "work")
        solved = solve_work(work)

        reset!
        host! host_for(@tenant)
        event("identify", identifier: "ada@example.com")

        body = event("signup", **DETAILS, **solved)

        assert_includes body["warnings"], "work-unsolved"
      end

      test "an expired challenge is held back" do
        policy!

        solved = solve_work(event("identify", identifier: "ada@example.com").dig("signup", "work"))

        travel(ProofOfWork::LIFETIME + 1.minute) do
          body = event("signup", **DETAILS, **solved)

          assert_includes body["warnings"], "work-unsolved"
        end
      end

      test "going back to edit the details does not ask for the work again" do
        policy!

        work = event("identify", identifier: "ada@example.com").dig("signup", "work")
        event("signup", **DETAILS, **solve_work(work))

        body = event("signup-edit")

        assert_equal "signup", body["prompt"]
        assert_nil body.dig("signup", "work")

        body = event("signup", nickname: "lovelace", email: "ada@example.com")

        assert_equal "signup-credentials", body["prompt"]
      end

      test "a policy with the check at 0 asks for no work" do
        policy!(proof_of_work: 0)

        body = event("identify", identifier: "ada@example.com")

        assert_nil body.dig("signup", "work")
        assert_equal "signup-credentials", event("signup", **DETAILS)["prompt"]
      end

      test "the first account on a server is not asked for work" do
        tenant = Tenant.create!(subdomain: "fresh-#{SecureRandom.hex(4)}", name: "Fresh")
        host! host_for(tenant)

        body = event("identify", identifier: "owner")

        assert_equal "signup", body["prompt"]
        assert_nil body.dig("signup", "work")
      end

      test "without JavaScript, signup says it needs JavaScript and offers no way to continue" do
        policy!

        post "/login", params: { event: "identify", identifier: "ada@example.com" }
        follow_redirect!

        assert_select "#signup .note-warn", text: I18n.t("logins.signing_up.needs_script")
        assert_select "#signup button[value=signup]", false
      end

      test "a policy holds a difficulty from 0 to 28 bits" do
        policy!(proof_of_work: 12)

        assert_equal 12, within(@tenant) { SignInPolicy.find_by(key: "open").proof_of_work }
        refute within(@tenant) { SignInPolicy.new(key: "hard", name: "Hard", proof_of_work: 40).valid? }
      end
    end
  end
end
