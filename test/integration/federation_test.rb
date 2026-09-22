module Masks
  module Server
    require "test_helper"
    require_relative "../support/upstream"
    require_relative "../support/saml_idp"

    class FederationTest < ActionDispatch::IntegrationTest
      include Federated

      def github!(**attributes)
        within(@tenant) do
          Provider.create!(
            key: "github", name: "GitHub", protocol: "oauth2", role: "delegate", trusts_email: true,
            authorization_url: @upstream.url("/gh/authorize"),
            token_url: @upstream.url("/gh/token"),
            userinfo_url: @upstream.url("/gh/user"),
            emails_url: @upstream.url("/gh/emails"),
            subject_claim: "id",
            claims: { "preferred_username" => "login", "name" => "name", "picture" => "avatar_url" },
            client_id: "upstream-client", client_secret: "upstream-secret",
            **attributes
          )
        end
      end

      def apple!
        @apple_key = OpenSSL::PKey::EC.generate("prime256v1")

        create_provider(
          key: "apple", name: "Apple",
          token_auth_method: "signed_secret", response_mode: "form_post",
          team_id: "TEAM123", key_id: "KEY456", private_key: @apple_key.to_pem,
          scopes: "name email", trusts_email: true, role: "delegate"
        )
      end

      def github_user(**overrides)
        { "id" => 42, "login" => "grace", "name" => "Grace Hopper",
          "avatar_url" => "https://avatars.test/42", "email" => "public@elsewhere.test" }.merge(overrides)
      end

      def return_from(key, handoff, **params)
        get "/login/provider/#{key}/callback", params: { code: "upstream-code", state: handoff["state"] }.merge(params)
      end

      setup do
        create_actor(@tenant, nickname: "owner", email: "owner@acme.test")
      end

      test "a plain oauth2 provider signs somebody in through its userinfo and its verified addresses" do
        github!
        @upstream.route("/gh/token", "access_token" => "gh-access", "token_type" => "bearer")
        @upstream.route("/gh/user", github_user)
        @upstream.route("/gh/emails") do
          [ { "email" => "public@elsewhere.test", "primary" => false, "verified" => false },
            { "email" => "grace@acme.test", "primary" => true, "verified" => true } ]
        end

        handoff = begin_sso(key: "github")

        assert_nil handoff["nonce"]
        assert_equal "S256", handoff["code_challenge_method"]

        return_from("github", handoff)

        actor = signed_in_actor

        assert actor, refusals.join("; ")
        assert_equal "grace", actor.nickname
        assert_equal "grace@acme.test", actor.email
        assert_equal "Grace Hopper", actor.name
        assert_equal "42", within(@tenant) { Connection.live.find_by(actor: actor).subject }
        assert_equal "Bearer gh-access", @upstream.headers_for("/gh/user").last["authorization"]
        assert @upstream.bodies_for("/gh/token").last["code_verifier"].present?
      end

      test "an address the provider only shows publicly is never taken as confirmed" do
        github!
        @upstream.route("/gh/token", "access_token" => "gh-access")
        @upstream.route("/gh/user", github_user)

        return_from("github", begin_sso(key: "github"))

        actor = signed_in_actor

        assert actor, refusals.join("; ")
        assert_nil actor.email
      end

      test "a subject nested in the profile is found by its path" do
        github!(subject_claim: "data.id", claims: { "preferred_username" => "data.username" })
        @upstream.route("/gh/token", "access_token" => "x-access")
        @upstream.route("/gh/user", "data" => { "id" => "1234", "username" => "grace" })

        return_from("github", begin_sso(key: "github"))

        assert_equal "1234", within(@tenant) { Connection.live.sole.subject }
      end

      test "a provider that authenticates with basic auth keeps the secret out of the body" do
        github!(token_auth_method: "client_secret_basic")
        @upstream.route("/gh/token", "access_token" => "gh-access")
        @upstream.route("/gh/user", github_user)

        return_from("github", begin_sso(key: "github"))

        sent = @upstream.bodies_for("/gh/token").last
        header = @upstream.headers_for("/gh/token").last["authorization"]

        assert_nil sent["client_secret"]
        assert_equal "Basic #{Base64.strict_encode64('upstream-client:upstream-secret')}", header
      end

      test "an apple sign-in posts back, signs its own secret, and names the person once" do
        apple!

        handoff = begin_sso(key: "apple")

        assert_equal "form_post", handoff["response_mode"]
        assert_includes handoff["scope"].split, "name"

        @upstream.announce("sub" => "apple-1", "email" => "grace@privaterelay.test",
                           "email_verified" => "true", "nonce" => handoff["nonce"])

        post "/login/provider/apple/callback", params: {
          code: "upstream-code", state: handoff["state"],
          user: { name: { firstName: "Grace", lastName: "Hopper" } }.to_json
        }

        assert_response :see_other
        assert_match %r{/login/provider/apple/callback\?posted=}, response.location

        follow_redirect!

        actor = signed_in_actor

        assert actor, refusals.join("; ")
        assert_equal "Grace Hopper", actor.name
        assert_equal "grace@privaterelay.test", actor.email

        secret = @upstream.bodies_for("/o/token").last["client_secret"]
        claims, header = JWT.decode(secret, @apple_key, true, algorithms: [ "ES256" ])

        assert_equal "KEY456", header["kid"]
        assert_equal "TEAM123", claims["iss"]
        assert_equal "upstream-client", claims["sub"]
        assert_equal @upstream.url, claims["aud"]
      end

      test "a posted callback is redeemed once" do
        apple!

        handoff = begin_sso(key: "apple")
        @upstream.announce("sub" => "apple-2", "email_verified" => "true", "nonce" => handoff["nonce"])

        post "/login/provider/apple/callback", params: { code: "upstream-code", state: handoff["state"] }
        location = response.location

        reset!
        host! host_for(@tenant)
        get location

        assert_nil signed_in_actor
      end

      test "somebody signed in links a provider from their account page" do
        create_provider
        ada = create_actor(@tenant, nickname: "ada", email: "ada@acme.test")

        sign_in_as(ada)
        post "/account/connections", params: { provider: "acme" }

        assert_response :redirect

        handoff = Rack::Utils.parse_query(URI.parse(response.location).query)
        @upstream.announce("sub" => "ada-upstream", "email" => "ada@acme.test", "email_verified" => true,
                           "nonce" => handoff["nonce"])

        return_from("acme", handoff)

        assert_redirected_to "/#connections"
        assert_equal ada.id, within(@tenant) { Connection.live.find_by(subject: "ada-upstream")&.actor_id }
      end

      test "an upstream account linked to somebody else is not taken over by linking it" do
        create_provider
        ada = create_actor(@tenant, nickname: "ada", email: "ada@acme.test")
        eve = create_actor(@tenant, nickname: "eve", email: "eve@acme.test")
        provider = within(@tenant) { Provider.find_by!(key: "acme") }
        within(@tenant) { Connection.record!(provider: provider, actor: ada, identity: { "sub" => "shared" }) }

        sign_in_as(eve)
        post "/account/connections", params: { provider: "acme" }

        handoff = Rack::Utils.parse_query(URI.parse(response.location).query)
        @upstream.announce("sub" => "shared", "nonce" => handoff["nonce"])

        return_from("acme", handoff)

        assert_equal ada.id, within(@tenant) { Connection.find_by(subject: "shared").actor_id }
        assert_match "already connected", flash[:alert]
      end

      test "linking asks for a recent sign-in" do
        create_provider
        ada = create_actor(@tenant, nickname: "ada", email: "ada@acme.test")

        sign_in_as(ada)
        travel 20.minutes

        post "/account/connections", params: { provider: "acme" }

        assert_redirected_to "/#connections"
        assert_match "Sign in again", flash[:alert]
      end

      test "a linking callback from another browser links nothing" do
        create_provider
        ada = create_actor(@tenant, nickname: "ada", email: "ada@acme.test")

        sign_in_as(ada)
        post "/account/connections", params: { provider: "acme" }
        handoff = Rack::Utils.parse_query(URI.parse(response.location).query)

        reset!
        host! host_for(@tenant)
        @upstream.announce("sub" => "stolen", "nonce" => handoff["nonce"])
        return_from("acme", handoff)

        assert_nil within(@tenant) { Connection.find_by(subject: "stolen") }
      end

      test "a preset fills in a provider from the few things it asks for" do
        attributes = ProviderPreset.find("keycloak").attributes("domain" => "ID.acme.test", "realm" => "Staff")

        assert_equal "https://id.acme.test/realms/Staff", attributes[:issuer]
        assert_equal "keycloak", attributes[:preset]

        assert_raises(ProviderPreset::Unusable) do
          ProviderPreset.find("okta").attributes("domain" => "evil.test/@elsewhere")
        end

        assert_raises(ProviderPreset::Unusable) { ProviderPreset.find("microsoft").attributes({}) }
      end

      test "every preset builds a provider that validates once it has credentials" do
        within(@tenant) do
          ProviderPreset.all.reject(&:custom?).each do |preset|
            values = preset.asks.index_with { |variable| variable == "domain" ? "id.acme.test" : "acme" }
            provider = Provider.new(key: preset.key, name: preset.name, client_id: "id", client_secret: "secret",
                                    **preset.attributes(values))

            provider.authorization_url ||= "https://id.acme.test/authorize"
            provider.token_url ||= "https://id.acme.test/token"

            if provider.saml?
              idp = SamlIdp.new
              provider.assign_attributes(Federation::Saml.parse_metadata(idp.metadata))
            end

            if provider.signs_its_secret?
              provider.assign_attributes(team_id: "T", key_id: "K", private_key: OpenSSL::PKey::EC.generate("prime256v1").to_pem)
            end

            assert provider.valid?, "#{preset.key}: #{provider.errors.full_messages.join('; ')}"
          end
        end
      end
    end
  end
end
