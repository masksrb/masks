module Masks
  module Server
    require "test_helper"

    class ManageRolesTest < ActionDispatch::IntegrationTest
      ROLES = Scopes.join(ManageRoles::SCOPES)

      setup do
        host! host_for(@tenant)

        @owner = create_actor(@tenant, nickname: "owner", scopes: "openid profile email masks:manage")
        @client = create_client(
          @tenant,
          allowed_scopes: "openid profile email #{ROLES}",
          approved_at: Time.current,
          grant_types: [ "authorization_code", "refresh_token" ]
        )
      end

      def manager(role, nickname: role.split(":").last)
        create_actor(@tenant, nickname: nickname, scopes: "openid profile email #{role}")
      end

      def bearer_for(actor, scope: "openid #{ROLES}")
        reset!
        host! host_for(@tenant)
        sign_in_as(actor)
        authorize(client_id: @client.client_id, scope: scope, resource: issuer_for(@tenant).manage_resource)
        consent! if awaiting_consent?

        token(grant_type: "authorization_code", code: code_from, redirect_uri: OidcFlow::REDIRECT_URI,
              code_verifier: verifier, client_id: @client.client_id)["access_token"]
      end

      def ask(query, token, **variables)
        post "/manage/graphql",
             params: { query: query, variables: variables }.to_json,
             headers: { "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer #{token}" }

        JSON.parse(response.body)
      end

      def refusal(body)
        body["errors"]&.first&.dig("message")
      end

      test "a reader reads everything and changes nothing" do
        held = bearer_for(manager(ManageRoles::READ))

        assert_equal [ "read" ], ask("{ manageLevels }", held).dig("data", "manageLevels")
        assert ask("{ actors { uuid } tenant { name } }", held).dig("data", "actors").any?

        body = ask(%(mutation { updateTenant(name: "Mine") { tenant { name } } }), held)

        assert_match "needs masks:manage", refusal(body)
        refute_equal "Mine", @tenant.reload.name
      end

      test "a token only carries the roles the person holds, whatever the console asks for" do
        held = bearer_for(manager(ManageRoles::SUPPORT))

        assert_equal %w[read support], ask("{ manageLevels }", held).dig("data", "manageLevels")
        assert_equal [ Scopes::OPENID, ManageRoles::SUPPORT ].sort, Scopes.list(claims_in(held)["scope"]).sort
      end

      test "support helps a person with their account and cannot touch keys or policies" do
        person = create_actor(@tenant, nickname: "person", scopes: "openid")
        held = bearer_for(manager(ManageRoles::SUPPORT))

        body = ask(%(mutation($uuid: ID!) { signOutActor(uuid: $uuid) { actor { uuid } } }), held, uuid: person.uuid)

        assert_nil body["errors"], body

        body = ask(%(mutation { rotateSigningKey { signingKey { kid } } }), held)

        assert_match "needs masks:manage or masks:manage:security", refusal(body)
      end

      test "security changes keys and policies and cannot touch people" do
        person = create_actor(@tenant, nickname: "person", scopes: "openid")
        held = bearer_for(manager(ManageRoles::SECURITY))

        body = ask(%(mutation { createSignInPolicy(key: "strict", name: "Strict") { signInPolicy { key } } }), held)

        assert_nil body["errors"], body

        body = ask(%(mutation($uuid: ID!) { signOutActor(uuid: $uuid) { actor { uuid } } }), held, uuid: person.uuid)

        assert_match "needs masks:manage or masks:manage:support", refusal(body)
      end

      test "support cannot change another manager, so it cannot take over an owner" do
        held = bearer_for(manager(ManageRoles::SUPPORT))

        body = ask(%(mutation($uuid: ID!) { updateActor(uuid: $uuid, email: "mine@example.com") { actor { uuid } } }),
                   held, uuid: @owner.uuid)

        assert_equal "only an owner can change another manager", refusal(body)
        refute_equal "mine@example.com", @owner.reload.email

        session = within { Session.start!(actor: @owner) }

        body = ask(%(mutation($id: ID!) { revokeSession(id: $id) { session { id } } }), held, id: session.id.to_s)

        assert_equal "only an owner can change another manager", refusal(body)
      end

      test "only an owner hands out a manage role, to a person or to a client" do
        security = bearer_for(manager(ManageRoles::SECURITY))

        body = ask(%(mutation { createClient(name: "Sly", allowedScopes: ["masks:manage"]) { client { clientId } } }), security)

        assert_match "only an owner can hand out masks:manage", refusal(body)

        support = bearer_for(manager(ManageRoles::SUPPORT, nickname: "helper"))

        body = ask(%(mutation { createActor(nickname: "new", scopes: ["openid", "masks:manage:read"]) { actor { uuid } } }), support)

        assert_match "only an owner can hand out masks:manage:read", refusal(body)

        body = ask(%(mutation($uuid: ID!, $scopes: [String!]!) { setActorScopes(uuid: $uuid, scopes: $scopes) { actor { uuid } } }),
                   support, uuid: create_actor(@tenant, nickname: "plain", scopes: "openid").uuid, scopes: [ "masks:manage" ])

        assert_match "needs masks:manage", refusal(body)
      end

      test "security cannot repoint a client that can carry a manage scope" do
        held = bearer_for(manager(ManageRoles::SECURITY))

        body = ask(%(mutation($id: ID!) { updateClient(clientId: $id, name: "Mine") { client { name } } }), held, id: @client.client_id)

        assert_equal "only an owner can change a client that can carry a manage scope", refusal(body)
      end

      test "an owner does everything" do
        held = bearer_for(@owner)

        assert_equal %w[read support security owner], ask("{ manageLevels }", held).dig("data", "manageLevels")

        body = ask(%(mutation { updateTenant(name: "Renamed") { tenant { name } } }), held)

        assert_equal "Renamed", body.dig("data", "updateTenant", "tenant", "name")
      end

      test "a role taken away stops working on the next request" do
        reader = manager(ManageRoles::READ)
        held = bearer_for(reader)

        within { reader.update!(scopes: "openid profile email") }

        ask("{ viewer { uuid } }", held)

        assert_response :unauthorized
      end

      test "security creates an organization, and support fills it with people" do
        security = bearer_for(manager(ManageRoles::SECURITY))

        body = ask(%(mutation { createOrganization(key: "acme", name: "Acme", roles: ["billing"]) { organization { roles } } }), security)

        assert_equal %w[owner member billing], body.dig("data", "createOrganization", "organization", "roles")

        support = bearer_for(manager(ManageRoles::SUPPORT, nickname: "helper"))

        body = ask(%(mutation { createOrganization(key: "globex", name: "Globex") { organization { key } } }), support)

        assert_match "needs masks:manage or masks:manage:security", refusal(body)

        body = ask(%(mutation { addMember(organization: "acme", email: "new@acme.example", role: "owner") { invited membership { role actor { email activated } } } }), support)

        assert body.dig("data", "addMember", "invited"), body
        assert_equal "owner", body.dig("data", "addMember", "membership", "role")
        refute body.dig("data", "addMember", "membership", "actor", "activated")

        body = ask(%(mutation { addMember(organization: "acme", email: "owner@example.invalid", role: "member") { invited } }), support)

        assert_equal "only an owner can change another manager", refusal(body)
      end

      test "the last owner of an organization cannot be removed or demoted" do
        person = create_actor(@tenant, nickname: "person", scopes: "openid")
        within { Organization.create!(key: "acme", name: "Acme").memberships.create!(actor: person, role: "owner") }

        held = bearer_for(manager(ManageRoles::SUPPORT))

        body = ask(%(mutation($uuid: ID!) { removeMember(organization: "acme", uuid: $uuid) { organization { key } } }), held, uuid: person.uuid)

        assert_equal "Acme needs an owner", refusal(body)

        body = ask(%(mutation($uuid: ID!) { setMemberRole(organization: "acme", uuid: $uuid, role: "member") { membership { role } } }), held, uuid: person.uuid)

        assert_match "needs an owner", refusal(body)
      end

      test "security gives an organization its own sign-in policy and a provisioning token" do
        within do
          Organization.create!(key: "acme", name: "Acme")
          SignInPolicy.create!(key: "strict", name: "Strict", second_factor_required: true)
        end

        held = bearer_for(manager(ManageRoles::SECURITY))

        body = ask(%(mutation { updateOrganization(key: "acme", signInPolicy: "strict") { organization { signInPolicy { key } } } }), held)

        assert_equal "strict", body.dig("data", "updateOrganization", "organization", "signInPolicy", "key")

        body = ask(%(mutation { issueProvisioningToken(label: "Acme Entra", organization: "acme") { secret provisioningToken { organization { key } } } }), held)

        assert_equal "acme", body.dig("data", "issueProvisioningToken", "provisioningToken", "organization", "key")

        body = ask(%(mutation { updateOrganization(key: "acme", signInPolicy: "") { organization { signInPolicy { key } } } }), held)

        assert_nil body.dig("data", "updateOrganization", "organization", "signInPolicy")
      end

      test "every mutation in the schema declares the least role it needs" do
        undeclared = ManageSchema.mutation.fields.values.reject { |field| field.resolver.level_declared }

        assert_empty undeclared.map(&:name)
      end
    end
  end
end
