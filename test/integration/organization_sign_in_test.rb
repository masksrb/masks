module Masks
  module Server
    require "test_helper"
    require_relative "../support/upstream"

    class OrganizationSignInTest < ActionDispatch::IntegrationTest
      include Federated

      SCOPE = "openid profile email offline_access organization".freeze

      setup do
        @registration = register(scope: SCOPE)
        host! host_for(@tenant)
        @acme = within { Organization.create!(key: "acme", name: "Acme", roles: [ "admin" ]) }
        @globex = within { Organization.create!(key: "globex", name: "Globex") }
      end

      def join(organization, actor, role = "member")
        within { organization.memberships.create!(actor: actor, role: role) }
      end

      def strict(organization)
        within do
          SignInPolicy.create!(key: "#{organization.key}-strict", name: "Strict", apps_require_second_factor: true)
            .tap { |policy| organization.update!(sign_in_policy: policy) }
        end
      end

      def ask_app(**params)
        authorize(client_id: @registration["client_id"], scope: SCOPE, **params)
      end

      def governed(organization, **attributes)
        within do
          SignInPolicy.create!(key: "#{organization.key}-own", name: "Own", **attributes)
            .tap { |policy| organization.update!(sign_in_policy: policy) }
        end
      end

      def arrived
        follow_redirect! while response.redirect? && URI.parse(response.location).host.to_s.end_with?(".auth.test")
        consent! if awaiting_consent?
        code_from
      end

      test "a password does not reach an organization whose policy asks for a passkey" do
        actor = create_actor(email: "ada@probe.example.com")
        join(@acme, actor)
        governed(@acme, first_factors: [ "passkey" ])

        sign_in_as(actor)
        ask_app(organization: "acme")

        assert_equal "first-factor", auth_data["prompt"]
        assert_includes auth_data["warnings"], "organization-sign-in"
        assert_equal false, auth_data.dig("password", "offered")
      end

      test "a password does not reach an organization chosen from several whose policy asks for a passkey" do
        actor = create_actor(email: "ada@probe.example.com")
        join(@acme, actor)
        join(@globex, actor)
        governed(@acme, first_factors: [ "passkey" ])

        sign_in_as(actor)
        ask_app
        advance!("organization", organization: "acme")

        assert_equal "first-factor", auth_data["prompt"]
      end

      test "a sign-in the organization's policy allows goes straight through" do
        actor = create_actor(email: "ada@probe.example.com")
        join(@acme, actor)
        governed(@acme, first_factors: [ "password" ])

        sign_in_as(actor)
        ask_app(organization: "acme")

        assert arrived.present?
      end

      test "an address outside the organization's domains is refused" do
        actor = create_actor(email: "ada@probe.example.com")
        join(@acme, actor)
        governed(@acme, email_domains: [ "acme.test" ])

        sign_in_as(actor)
        ask_app(organization: "acme")

        assert_equal "access_denied", redirected["error"]
      end

      test "a provider the organization's policy does not list sends the person back to sign in" do
        create_provider(role: "delegate", email_domains: "acme.test", organization: @acme)
        create_actor(nickname: "owner", email: "owner@acme.test")
        governed(@acme, first_factors: %w[password provider], providers: [ "okta" ])

        ask_app(organization: "acme")
        finish_sso(sub: "upstream-9", email: "grace@acme.test", handoff: begin_sso(rid: current_rid))
        follow_redirect! while response.redirect? && URI.parse(response.location).host.to_s.end_with?(".auth.test")

        assert_equal "first-factor", auth_data["prompt"]
      end

      test "the organization's own provider signs a person in, and a password later does not" do
        create_provider(role: "delegate", email_domains: "acme.test", organization: @acme)
        create_actor(nickname: "owner", email: "owner@acme.test")
        governed(@acme, first_factors: [ "provider" ], providers: [ "acme" ])

        ask_app(organization: "acme")
        finish_sso(sub: "upstream-9", email: "grace@acme.test", handoff: begin_sso(rid: current_rid))

        assert arrived.present?

        ask_app(organization: "acme", state: "again")

        assert arrived.present?, "the session remembers it came through the organization's provider"

        grace = within { Actor.find_by!(email: "grace@acme.test").tap { |held| held.update!(nickname: "grace", password: "password") } }

        reset!
        host! host_for(@tenant)
        sign_in_as(grace)
        ask_app(organization: "acme")

        assert_equal "first-factor", auth_data["prompt"]
      end

      test "an organization's policy governs a request that names it" do
        actor = create_actor(email: "ada@probe.example.com")
        join(@acme, actor)
        strict(@acme)

        sign_in_as(actor)
        enable_otp(actor)
        ask_app(organization: "acme")

        assert_equal "second-factor", auth_data["prompt"]
      end

      test "an app without the organization scope that names an organization refuses a person outside it" do
        actor = create_actor(email: "ada@probe.example.com")
        registration = register(scope: "openid profile")
        within { SignInPolicy.create!(key: "acme-lax", name: "Lax").tap { |policy| @acme.update!(sign_in_policy: policy) } }

        sign_in_as(actor)
        authorize(client_id: registration["client_id"], scope: "openid profile", organization: "acme")

        assert_equal "access_denied", redirected["error"]
      end

      test "an organization's policy takes over once a person chooses it" do
        actor = create_actor(email: "ada@probe.example.com")
        join(@acme, actor)
        join(@globex, actor)
        strict(@acme)

        sign_in_as(actor)
        enable_otp(actor)
        ask_app

        assert_equal "choose-organization", auth_data["prompt"]

        advance!("organization", organization: "acme")

        assert_equal "second-factor", auth_data["prompt"]
      end

      test "another organization's policy does not reach a person who chose elsewhere" do
        actor = create_actor(email: "ada@probe.example.com")
        join(@acme, actor)
        join(@globex, actor)
        strict(@acme)

        sign_in_as(actor)
        enable_otp(actor)
        ask_app
        advance!("organization", organization: "globex")
        consent! if awaiting_consent?

        assert code_from.present?
      end

      test "an organization's provider is offered only to a request that names the organization" do
        create_provider(organization: @acme)
        create_actor(nickname: "owner", email: "owner@acme.test")

        get "/login"

        assert_nil auth_data["providers"]

        ask_app(organization: "acme")

        assert_equal [ "acme" ], auth_data["providers"].map { |held| held["key"] }

        ask_app(organization: "globex")

        assert_nil auth_data["providers"]
      end

      test "signing in through an organization's provider makes a member in the role the groups map to" do
        create_provider(role: "delegate", email_domains: "acme.test", organization: @acme,
                        role_map: { "Acme Admins" => "admin" })
        create_actor(nickname: "owner", email: "owner@acme.test")

        ask_app(organization: "acme")
        finish_sso(sub: "upstream-7", email: "grace@acme.test", groups: [ "Everyone", "Acme Admins" ],
                   handoff: begin_sso(rid: current_rid))

        actor = within { Actor.find_by(email: "grace@acme.test") }

        assert actor, refusals.join("; ")
        assert_equal "admin", within { @acme.memberships.find_by!(actor: actor).role }
        assert within { Event.exists?(action: Event::MEMBERSHIP_ADDED) }
      end

      test "a later sign-in through the provider moves the member to the role their groups map to now" do
        create_provider(role: "delegate", email_domains: "acme.test", organization: @acme,
                        role_map: { "Acme Admins" => "admin" })
        create_actor(nickname: "owner", email: "owner@acme.test")

        ask_app(organization: "acme")
        finish_sso(sub: "upstream-7", email: "grace@acme.test", groups: [ "Acme Admins" ],
                   handoff: begin_sso(rid: current_rid))

        reset!
        host! host_for(@tenant)
        ask_app(organization: "acme")
        finish_sso(sub: "upstream-7", email: "grace@acme.test", groups: [ "Everyone" ],
                   handoff: begin_sso(rid: current_rid))

        assert_equal "member", within { @acme.memberships.sole.role }
      end

      test "a provider's roles must be ones its organization offers" do
        provider = within { Provider.new(key: "p", name: "P", protocol: "oidc", organization: @globex, role_map: { "x" => "admin" }) }

        refute within { provider.valid? }
        assert_match "does not offer: admin", provider.errors[:role_map].to_sentence
      end

      test "a groups claim named by a URL maps roles too" do
        create_provider(role: "delegate", email_domains: "acme.test", organization: @acme,
                        role_claim: "https://acme.test/groups", role_map: { "Acme Admins" => "admin" })
        create_actor(nickname: "owner", email: "owner@acme.test")

        ask_app(organization: "acme")
        finish_sso(sub: "upstream-8", email: "grace@acme.test", "https://acme.test/groups": [ "Acme Admins" ],
                   handoff: begin_sso(rid: current_rid))

        actor = within { Actor.find_by(email: "grace@acme.test") }

        assert_equal "admin", within { @acme.memberships.find_by!(actor: actor).role }
      end
    end
  end
end
