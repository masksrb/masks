module Masks
  module Server
    require "test_helper"

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

      def app(**params)
        authorize(client_id: @registration["client_id"], scope: SCOPE, **params)
      end

      test "an organization's policy governs a request that names it" do
        actor = create_actor(email: "ada@probe.example.com")
        join(@acme, actor)
        strict(@acme)

        sign_in_as(actor)
        enable_otp(actor)
        app(organization: "acme")

        assert_equal "second-factor", auth_data["prompt"]
      end

      test "an organization's policy takes over once a person chooses it" do
        actor = create_actor(email: "ada@probe.example.com")
        join(@acme, actor)
        join(@globex, actor)
        strict(@acme)

        sign_in_as(actor)
        enable_otp(actor)
        app

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
        app
        advance!("organization", organization: "globex")
        consent! if awaiting_consent?

        assert code_from.present?
      end

      test "an organization's provider is offered only to a request that names the organization" do
        create_provider(organization: @acme)
        create_actor(nickname: "owner", email: "owner@acme.test")

        get "/login"

        assert_nil auth_data["providers"]

        app(organization: "acme")

        assert_equal [ "acme" ], auth_data["providers"].map { |held| held["key"] }

        app(organization: "globex")

        assert_nil auth_data["providers"]
      end

      test "signing in through an organization's provider makes a member in the role the groups map to" do
        create_provider(role: "delegate", email_domains: "acme.test", organization: @acme,
                        role_map: { "Acme Admins" => "admin" })
        create_actor(nickname: "owner", email: "owner@acme.test")

        app(organization: "acme")
        finish_sso(sub: "upstream-7", email: "grace@acme.test", groups: [ "Everyone", "Acme Admins" ],
                   handoff: begin_sso(rid: current_rid))

        actor = signed_in_actor

        assert actor, refusals.join("; ")
        assert_equal "admin", within { @acme.memberships.find_by!(actor: actor).role }
        assert within { Event.exists?(action: Event::MEMBERSHIP_ADDED) }
      end

      test "a later sign-in through the provider moves the member to the role their groups map to now" do
        create_provider(role: "delegate", email_domains: "acme.test", organization: @acme,
                        role_map: { "Acme Admins" => "admin" })
        create_actor(nickname: "owner", email: "owner@acme.test")

        app(organization: "acme")
        finish_sso(sub: "upstream-7", email: "grace@acme.test", groups: [ "Acme Admins" ],
                   handoff: begin_sso(rid: current_rid))

        reset!
        host! host_for(@tenant)
        app(organization: "acme")
        finish_sso(sub: "upstream-7", email: "grace@acme.test", groups: [ "Everyone" ],
                   handoff: begin_sso(rid: current_rid))

        assert_equal "member", within { @acme.memberships.sole.role }
      end

      test "a provider's roles must be ones its organization offers" do
        provider = within { Provider.new(key: "p", name: "P", protocol: "oidc", organization: @globex, role_map: { "x" => "admin" }) }

        refute within { provider.valid? }
        assert_match "does not offer: admin", provider.errors[:role_map].to_sentence
      end
    end
  end
end
