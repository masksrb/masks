module Masks
  module Server
    require "test_helper"

    class ScimGroupsTest < ActionDispatch::IntegrationTest
      BASE = "/scim/v2".freeze

      setup do
        host! host_for(@tenant)
        @manager = create_actor(nickname: "manager", scopes: "openid masks:manage")
        @acme = within { Organization.create!(key: "acme", name: "Acme", roles: [ "billing" ]) }
        within do
          provider = Provider.create!(key: "acme-idp", name: "Acme IdP", organization: @acme, issuer: "https://idp.acme.example",
                                      authorization_url: "https://idp.acme.example/authorize", token_url: "https://idp.acme.example/token",
                                      jwks_uri: "https://idp.acme.example/jwks", client_id: "c", client_secret: "s")
          DomainClaim.create!(domain: "acme.example", provider: provider).update_columns(verified_at: Time.current)
        end
        @founder = create_actor(nickname: "founder", email: "founder@example.com")
        within { Members.enroll!(@acme, @founder, role: "owner", by: nil) }
        @secret = within { ProvisioningToken.issue!(label: "Acme Entra", by: @manager, organization: @acme).secret }
      end

      def scim(method, path, body: nil, secret: @secret)
        send(method, "#{BASE}#{path}", params: body&.to_json,
                                       headers: { "CONTENT_TYPE" => Scim::MEDIA_TYPE, "HTTP_AUTHORIZATION" => "Bearer #{secret}" })

        response.body.present? ? JSON.parse(response.body) : nil
      end

      def provision(name)
        scim(:post, "/Users", body: { "schemas" => [ Scim::USER ], "userName" => "#{name}@acme.example", "active" => true })["id"]
      end

      def group(role)
        "#{@acme.uuid}.#{role}"
      end

      def regroup(role, *operations)
        scim(:patch, "/Groups/#{group(role)}", body: { "schemas" => [ Scim::PATCH ], "Operations" => operations })
      end

      def role_of(uuid)
        within { @acme.memberships.joins(:actor).find_by!(actors: { uuid: uuid }).role }
      end

      test "each of an organization's roles is a group, found by displayName or id" do
        ada = provision("ada")

        listed = scim(:get, "/Groups")

        assert_equal %w[owner member billing], listed["Resources"].map { |held| held["displayName"] }
        assert_equal [ @founder.uuid ], listed["Resources"].first["members"].map { |member| member["value"] }
        assert_equal [ ada ], listed["Resources"].second["members"].map { |member| member["value"] }

        found = scim(:get, "/Groups?filter=#{CGI.escape('displayName eq "Billing"')}")

        assert_equal [ group("billing") ], found["Resources"].map { |held| held["id"] }
        assert_equal [], found["Resources"].first["members"]

        shown = scim(:get, "/Groups/#{group('owner')}?excludedAttributes=members")

        assert_equal "owner", shown["displayName"]
        refute shown.key?("members")
        assert_equal "#{origin_for(@tenant)}#{BASE}/Groups/#{group('owner')}", shown.dig("meta", "location")

        scim(:get, "/Groups/#{SecureRandom.uuid}.owner")

        assert_response :not_found
      end

      test "okta adds a member to a role and the role replaces the one they held" do
        ada = provision("ada")

        regroup("billing", { "op" => "add", "path" => "members", "value" => [ { "value" => ada, "display" => "ada" } ] })

        assert_response :success
        assert_equal "billing", role_of(ada)

        event = within { Event.where(action: Event::MEMBERSHIP_ROLE_CHANGED).last }

        assert_equal({ "was" => "member", "now" => "billing", "via" => "scim" }, event.details.slice("was", "now", "via"))
      end

      test "entra removes a member by filter and they fall back to member" do
        ada = provision("ada")
        regroup("billing", { "op" => "add", "path" => "members", "value" => [ { "value" => ada } ] })

        regroup("billing", { "op" => "Remove", "path" => %(members[value eq "#{ada}"]) })

        assert_response :success
        assert_equal "member", role_of(ada)
      end

      test "a put replaces a group's members and leaves people the directory did not create alone" do
        ada = provision("ada")
        grace = provision("grace")
        regroup("owner", { "op" => "add", "path" => "members", "value" => [ { "value" => ada } ] })

        body = scim(:put, "/Groups/#{group('owner')}", body: { "schemas" => [ Scim::GROUP ], "displayName" => "owner",
                                                               "members" => [ { "value" => grace } ] })

        assert_response :success
        assert_equal "member", role_of(ada)
        assert_equal "owner", role_of(grace)
        assert_equal [ @founder.uuid, grace ].sort, body["members"].map { |member| member["value"] }.sort
      end

      test "someone the directory did not provision cannot be added, and nothing says whether they exist" do
        outsider = create_actor(nickname: "outsider", email: "outsider@example.com")

        answers = [ outsider.uuid, SecureRandom.uuid, @founder.uuid ].map do |uuid|
          body = regroup("billing", { "op" => "add", "path" => "members", "value" => [ { "value" => uuid } ] })

          [ response.status, body["detail"] ]
        end

        assert_equal 400, answers.first.first
        assert_equal 1, answers.uniq.size
        assert_equal "owner", role_of(@founder.uuid)
      end

      test "removing someone the directory did not provision is refused" do
        regroup("owner", { "op" => "remove", "path" => %(members[value eq "#{@founder.uuid}"]) })

        assert_response :forbidden
        assert_equal "owner", role_of(@founder.uuid)
      end

      test "the last owner keeps the role" do
        ada = provision("ada")
        regroup("owner", { "op" => "add", "path" => "members", "value" => [ { "value" => ada } ] })
        within { Members.assign!(@acme.memberships.find_by!(actor: @founder), role: "member", by: nil) }

        regroup("owner", { "op" => "remove", "path" => "members" })

        assert_response :conflict
        assert_equal "mutability", JSON.parse(response.body)["scimType"]
        assert_equal "owner", role_of(ada)
      end

      test "a changed role revokes the access tokens issued for the organization" do
        ada = provision("ada")
        token = within do
          actor = Actor.find_by!(uuid: ada)
          AccessToken.create!(actor: actor, organization: @acme, scopes: "openid", audience: [], digest: SecureRandom.uuid,
                              expires_at: 1.hour.from_now)
        end

        regroup("billing", { "op" => "add", "path" => "members", "value" => [ { "value" => ada } ] })

        refute within { token.reload.live? }
      end

      test "a directory creates a role with its first members and deletes it once nobody holds it" do
        ada = provision("ada")

        made = scim(:post, "/Groups", body: { "schemas" => [ Scim::GROUP ], "displayName" => "Support",
                                               "members" => [ { "value" => ada } ] })

        assert_response :created
        assert_equal group("support"), made["id"]
        assert_equal "support", role_of(ada)
        assert_includes within { @acme.reload.roles }, "support"

        scim(:post, "/Groups", body: { "schemas" => [ Scim::GROUP ], "displayName" => "support" })

        assert_response :conflict

        scim(:post, "/Groups", body: { "schemas" => [ Scim::GROUP ], "displayName" => "Front Desk" })

        assert_response :bad_request

        scim(:delete, "/Groups/#{group('support')}")

        assert_response :conflict

        regroup("support", { "op" => "remove", "path" => "members", "value" => [ { "value" => ada } ] })
        scim(:delete, "/Groups/#{group('support')}")

        assert_response :no_content
        refute_includes within { @acme.reload.roles }, "support"

        scim(:delete, "/Groups/#{group('owner')}")

        assert_response :bad_request
      end

      test "a group's name does not change" do
        regroup("billing", { "op" => "replace", "value" => { "id" => group("billing"), "displayName" => "finance" } })

        assert_response :bad_request
        assert_equal "mutability", JSON.parse(response.body)["scimType"]
      end

      test "a token for the whole tenant sees no groups and changes none" do
        tenant_wide = within { ProvisioningToken.issue!(label: "Entra", by: @manager).secret }

        assert_equal 0, scim(:get, "/Groups", secret: tenant_wide)["totalResults"]

        scim(:post, "/Groups", secret: tenant_wide, body: { "schemas" => [ Scim::GROUP ], "displayName" => "support" })

        assert_response :forbidden
      end

      test "the metadata advertises groups" do
        assert_equal %w[User Group], scim(:get, "/ResourceTypes")["Resources"].map { |type| type["id"] }
        assert_equal Scim::GROUP, scim(:get, "/Schemas/#{Scim::GROUP}")["id"]
        assert_equal "/Groups", scim(:get, "/ResourceTypes/Group")["endpoint"]
      end
    end
  end
end
