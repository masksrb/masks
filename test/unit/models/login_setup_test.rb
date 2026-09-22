module Masks
  module Server
    require "test_helper"

    class LoginSetupTest < ActiveSupport::TestCase
      PASSWORD = "a-long-enough-password".freeze

      setup do
        @store = {}
      end

      def step(event: nil, **updates)
        within do
          Login.new(store: @store, event: event, updates: updates).update
        end
      end

      def identify(nickname: "owner", email: "owner@example.invalid", **updates)
        step(event: "signup", token: @tenant.setup_token!, nickname: nickname, email: email, **updates)
      end

      def name_of(login)
        login.as_json.dig("signup", "name")
      end

      def credit(password: PASSWORD, confirmation: password)
        step(event: "signup", password: password, password_confirmation: confirmation)
      end

      def enrol
        secret = within { Login.new(store: @store).update.as_json }.dig("enrolment", "otp", "secret").delete(" ")

        step(event: "enrol:otp", code: ROTP::TOTP.new(secret).now)
        step(event: "enrol:done", kept: "1")
      end

      def configure(called: "Demo", **updates)
        step(event: "setup-configure", called: called, **updates)
      end

      def set_up(**updates)
        identify(**updates)
        credit
        enrol
        configure
      end

      def with_token(value)
        was = ::Rails.configuration.masks.setup_token
        ::Rails.configuration.masks.setup_token = value
        yield
      ensure
        ::Rails.configuration.masks.setup_token = was
      end

      test "a tenant with no actors asks to be set up before it asks who you are" do
        assert_equal "signup", step.prompt
      end

      test "the name and address are taken first, and nothing is created yet" do
        login = identify

        assert_equal "signup-credentials", login.prompt
        assert_nil login.actor
        assert_equal 0, within { Actor.count }
      end

      test "the credentials screen reads back what was entered" do
        identify(nickname: "owner", email: "owner@example.invalid", name: "Ada Lovelace")

        published = step.as_json["signup"]

        assert_equal "owner", published["nickname"]
        assert_equal "owner@example.invalid", published["email"]
        assert_equal "Ada Lovelace", published["name"]
      end

      test "a name is optional, and kept when it is given" do
        identify(name: "  Ada Lovelace  ")
        credit
        configure

        assert_equal "Ada Lovelace", within { Actor.sole.name }
      end

      test "no name is no obstacle" do
        login = set_up

        assert_nil login.actor.name
        assert_nil name_of(step)
      end

      test "the password creates the manager, who adds a second factor before anything is configured" do
        identify
        login = credit

        assert_equal "enrol", login.prompt
        assert_equal "setup-configure", enrol.prompt
        assert_equal "owner", login.actor.nickname
        assert_equal "owner", login.identifier
      end

      test "configuring settles the login and signs the manager in" do
        identify
        credit
        enrol
        login = configure(called: "Payroll")

        assert_equal "settled", login.prompt
        assert login.settled?
        assert_equal "Payroll", @tenant.reload.name
      end

      test "configuring names the installation" do
        identify
        credit
        enrol

        login = configure(called: "  Payroll  ")

        assert login.settled?
        assert_equal "Payroll", @tenant.reload.name
      end

      test "a name left as it was settles all the same" do
        identify
        credit
        enrol
        login = configure(called: "")

        assert login.settled?
        assert_equal "Demo", @tenant.reload.name
      end

      test "the configuration screen offers the name the tenant already holds" do
        identify
        credit
        enrol

        login = step
        published = within { login.as_json["configure"] }

        assert_equal @tenant.name, published["called"]
      end

      test "one post that carries everything creates the manager but still stops for a second factor" do
        login = step(event: "signup", token: @tenant.setup_token!, nickname: "owner", email: "owner@example.invalid",
                     password: PASSWORD, password_confirmation: PASSWORD,
                     called: "Payroll")

        assert_equal "enrol", login.prompt
        assert_equal "owner", login.actor.nickname
        assert_equal "Demo", @tenant.reload.name
      end

      test "setup cannot be finished without a second factor" do
        identify
        credit

        login = step(event: "enrol:done", kept: "1")

        assert_equal "enrol", login.prompt
        assert_includes login.warnings, "second-factor-required"

        login = configure(called: "Payroll")

        assert_equal "enrol", login.prompt
        assert_equal "Demo", @tenant.reload.name
      end

      test "a password the confirmation does not match creates nothing" do
        identify
        login = credit(password: PASSWORD, confirmation: "a-different-password")

        assert_equal "signup-credentials", login.prompt
        assert_includes login.warnings, "mismatched-password"
        assert_equal 0, within { Actor.count }
      end

      test "editing goes back to the first screen with the entries kept" do
        identify(nickname: "owner", email: "owner@example.invalid")

        login = step(event: "signup-edit")

        assert_equal "signup", login.prompt
        assert_equal "owner", login.as_json.dig("signup", "nickname")

        assert_equal "signup-credentials", identify(nickname: "second").prompt
        assert_equal "second", step.as_json.dig("signup", "nickname")
      end

      test "a password posted while editing creates nothing" do
        identify
        step(event: "signup-edit")

        login = credit

        assert_equal "signup", login.prompt
        assert_equal 0, within { Actor.count }
      end

      test "the owner holds the scopes masks defines, and masks:manage, and nothing else" do
        login = set_up

        assert_equal (Scopes::STANDARD + [ Scopes::MANAGE ]).sort, login.actor.scope_list.sort
      end

      test "an actor created any other way does not hold masks:manage" do
        login = set_up
        second = within { Actor.create!(nickname: "second", password: PASSWORD) }

        assert_includes login.actor.scope_list, Scopes::MANAGE
        refute_includes second.scope_list, Scopes::MANAGE
      end

      test "the owner can sign in afterwards with the password they chose" do
        set_up

        assert_equal "owner", within { Actor.authenticate("owner", PASSWORD) }&.nickname
      end

      test "the owner's email is required, and starts unconfirmed" do
        login = set_up

        assert_equal "owner@example.invalid", login.actor.email
        assert_nil login.actor.email_verified_at
      end

      test "setup without an email warns rather than moving on" do
        login = identify(nickname: "solo", email: nil)

        assert_equal "signup", login.prompt
        assert_includes login.warnings, "missing-email"
        assert_equal 0, within { Actor.count }
      end

      test "the prompt is gone the moment an actor exists" do
        create_actor

        assert_equal "identify", step.prompt
      end

      test "a second tenant is set up independently of the first" do
        create_actor

        assert_equal "identify", step.prompt
        assert_equal "signup", within(other_tenant) {
          Login.new(store: {}, event: nil, updates: {}).update
        }.prompt
      end

      test "a blank nickname does not move on" do
        login = identify(nickname: " ")

        assert_equal "signup", login.prompt
        assert_includes login.warnings, "missing-nickname"
        assert_equal 0, within { Actor.count }
      end

      test "a short password does not create anything" do
        identify
        login = credit(password: "short")

        assert_equal "signup-credentials", login.prompt
        assert_includes login.warnings, "short-password"
        assert_equal 0, within { Actor.count }
      end

      test "a nickname the model refuses warns rather than raising" do
        identify(nickname: "-nope-")
        login = credit

        assert_equal "signup-credentials", login.prompt
        assert_includes login.warnings, "invalid-account"
        assert_equal 0, within { Actor.count }
      end

      test "a first run asks for the setup token even when none was configured" do
        assert step.as_json.dig("signup", "token")
        assert_match(/\A[1-9A-HJ-NP-Za-km-z]{32}\z/, @tenant.setup_token!)
      end

      test "a wrong setup token creates nothing" do
        login = identify(token: "not-the-token")

        assert_equal "signup", login.prompt
        assert_includes login.warnings, "invalid-setup-token"
        assert_equal 0, within { Actor.count }
      end

      test "a missing setup token is refused rather than treated as blank" do
        login = identify(token: nil)

        assert_equal "signup", login.prompt
        assert_includes login.warnings, "invalid-setup-token"
        assert_equal 0, within { Actor.count }
      end

      test "one tenant's setup token does not set up another" do
        login = identify(token: other_tenant.setup_token!)

        assert_includes login.warnings, "invalid-setup-token"
        assert_equal 0, within { Actor.count }
      end

      test "the setup token is the tenant's own, and stays the same until it is used" do
        first = @tenant.setup_token!

        assert_equal first, Tenant.find(@tenant.id).setup_token!
      end

      test "the setup token is kept encrypted" do
        token = @tenant.setup_token!
        stored = Tenant.connection.select_value("SELECT setup_token FROM tenants WHERE id = #{@tenant.id}")

        refute_includes stored, token
      end

      test "a setup token pinned at deploy stands in for the one the tenant minted" do
        with_token("the-real-token") do
          assert_equal "signup-credentials", identify(token: "the-real-token").prompt
        end
      end

      test "going back to edit does not ask for the setup token again" do
        identify
        login = step(event: "signup-edit")

        refute login.as_json.dig("signup", "token")
        assert_equal "signup-credentials", step(event: "signup", nickname: "second", email: "owner@example.invalid").prompt
      end

      test "the setup token is spent once the owner exists" do
        identify
        credit

        assert_nil @tenant.reload.setup_token
      end

      test "the setup key stops being published once the tenant is set up" do
        set_up

        assert_nil step.as_json["signup"]
      end
    end
  end
end
