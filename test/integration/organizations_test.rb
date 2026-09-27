module Masks
  module Server
    require "test_helper"

    class OrganizationsTest < ActionDispatch::IntegrationTest
      SCOPE = "openid profile email offline_access organization".freeze

      setup do
        @actor = create_actor(email: "ada@probe.example.com")
        @registration = register(scope: SCOPE)
        host! host_for(@tenant)

        @acme = organization("acme", "Acme")
        @globex = organization("globex", "Globex")
      end

      def organization(key, name, roles: [])
        within { Organization.create!(key: key, name: name, roles: roles) }
      end

      def join(organization, role = "member", actor: @actor)
        within { organization.memberships.create!(actor: actor, role: role) }
      end

      def signed_in_to_app(**params)
        sign_in_as(@actor)
        authorize(client_id: @registration["client_id"], scope: SCOPE, **params)
        consent! if awaiting_consent?
      end

      def tokens
        token(grant_type: "authorization_code", code: code_from, redirect_uri: OidcFlow::REDIRECT_URI,
              code_verifier: verifier, client_id: @registration["client_id"],
              client_secret: @registration["client_secret"])
      end

      test "a person in one organization signs in as a member of it without being asked" do
        join(@acme, "owner")

        signed_in_to_app
        body = tokens

        assert_equal({ "id" => @acme.uuid, "key" => "acme", "name" => "Acme", "role" => "owner" }, claims_in(body["access_token"])["org"])
        assert_equal "acme", claims_in(body["id_token"]).dig("org", "key")
      end

      test "a person in several organizations chooses one" do
        join(@acme)
        join(@globex, "owner")

        sign_in_as(@actor)
        authorize(client_id: @registration["client_id"], scope: SCOPE)

        assert_equal "choose-organization", auth_data["prompt"]
        assert_equal %w[acme globex], auth_data["organizations"].map { |held| held["key"] }

        advance!("organization", organization: "globex")
        consent! if awaiting_consent?

        assert_equal({ "key" => "globex", "role" => "owner" }, claims_in(tokens["access_token"])["org"].slice("key", "role"))
      end

      test "an app that names the organization skips the choice" do
        join(@acme)
        join(@globex)

        signed_in_to_app(organization: "acme")

        assert_equal "acme", claims_in(tokens["access_token"]).dig("org", "key")
      end

      test "an app that names an organization the person is not in is refused" do
        join(@acme)

        signed_in_to_app(organization: "globex")

        assert_equal "access_denied", redirected["error"]
      end

      test "choosing an organization the person is not in is refused" do
        join(@acme)
        join(@globex)

        sign_in_as(@actor)
        authorize(client_id: @registration["client_id"], scope: SCOPE)
        advance!("organization", organization: "initech")

        assert_equal "access_denied", redirected["error"]
      end

      test "a person in no organization is refused by an app that asks for one" do
        signed_in_to_app

        assert_equal "access_denied", redirected["error"]
      end

      test "an app that does not ask for the organization scope gets no claim and no question" do
        join(@acme)
        join(@globex)

        sign_in_as(@actor)
        authorize(client_id: @registration["client_id"], scope: "openid profile")
        consent! if awaiting_consent?

        assert_nil claims_in(tokens["access_token"])["org"]
      end

      test "an archived organization is not offered" do
        join(@acme)
        join(@globex)
        within { @globex.archive! }

        signed_in_to_app

        assert_equal "acme", claims_in(tokens["access_token"]).dig("org", "key")
      end

      test "userinfo and introspection name the organization, and introspection answers the role held now" do
        membership = join(@acme)

        signed_in_to_app
        access = tokens["access_token"]

        get "/userinfo", headers: { "Authorization" => "Bearer #{access}" }

        assert_equal({ "id" => @acme.uuid, "key" => "acme", "name" => "Acme", "role" => "member" }, JSON.parse(response.body)["org"])

        within { membership.update!(role: "owner") }

        post "/introspect", params: { token: access, client_id: @registration["client_id"],
                                      client_secret: @registration["client_secret"] }

        assert_equal "owner", JSON.parse(response.body).dig("org", "role")
      end

      test "a refresh carries the current role, and stops once the person is removed" do
        membership = join(@acme)

        signed_in_to_app
        refresh = tokens["refresh_token"]

        within { membership.update!(role: "owner") }

        body = token(grant_type: "refresh_token", refresh_token: refresh, client_id: @registration["client_id"],
                     client_secret: @registration["client_secret"])

        assert_equal "owner", claims_in(body["access_token"]).dig("org", "role")

        within do
          join(@acme, "owner", actor: create_actor(nickname: "other"))
          membership.destroy!
        end

        refused = token(grant_type: "refresh_token", refresh_token: body["refresh_token"],
                        client_id: @registration["client_id"], client_secret: @registration["client_secret"])

        assert_equal "invalid_grant", refused["error"]
      end

      test "archiving an organization revokes the tokens issued for it" do
        join(@acme)

        signed_in_to_app
        refresh = tokens["refresh_token"]

        within { @acme.archive! }

        refused = token(grant_type: "refresh_token", refresh_token: refresh, client_id: @registration["client_id"],
                        client_secret: @registration["client_secret"])

        assert_equal "invalid_grant", refused["error"]
      end

      test "an organization always keeps an owner" do
        owner = join(@acme, "owner")

        within do
          refute owner.update(role: "member")
          refute owner.destroy
          assert owner.reload.persisted?
        end
      end

      test "a role an organization does not offer is refused" do
        within do
          membership = @acme.memberships.new(actor: @actor, role: "admin")

          refute membership.valid?
        end

        billing = organization("initech", "Initech", roles: [ "billing" ])

        assert join(billing, "billing").persisted?
      end

      test "what happens while signing in as a member is recorded against the organization" do
        join(@acme)

        signed_in_to_app
        tokens

        within do
          assert Event.where(action: Event::CONSENT_GRANTED, organization: @acme).exists?
          assert_nil Event.where(action: Event::SESSION_STARTED).first.organization_id, "the session began before any app asked"
        end
      end

      test "a pending membership grants no organization until it is accepted" do
        membership = within { @acme.memberships.create!(actor: @actor, role: "member", pending: true) }

        signed_in_to_app

        assert_equal "access_denied", redirected["error"]

        within { membership.accept! }
        reset!
        host! host_for(@tenant)
        signed_in_to_app

        assert_equal "acme", claims_in(tokens["access_token"]).dig("org", "key")
      end
    end
  end
end
