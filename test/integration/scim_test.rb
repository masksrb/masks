module Masks
  module Server
    require "test_helper"

    class ScimTest < ActionDispatch::IntegrationTest
      BASE = "/scim/v2".freeze

      setup do
        host! host_for(@tenant)
        @manager = create_actor(nickname: "manager", scopes: "openid masks:manage")
        @secret = within { ProvisioningToken.issue!(label: "Entra", by: @manager).secret }
      end

      def scim(method, path, body: nil, secret: @secret, headers: {})
        send(method, "#{BASE}#{path}",
             params: body&.to_json,
             headers: { "CONTENT_TYPE" => Scim::MEDIA_TYPE, "HTTP_AUTHORIZATION" => "Bearer #{secret}" }.merge(headers))

        response.body.present? ? JSON.parse(response.body) : nil
      end

      def provision(**attributes)
        scim(:post, "/Users", body: {
          "schemas" => [ Scim::USER ],
          "userName" => "ada@example.com",
          "externalId" => "entra-1",
          "name" => { "givenName" => "Ada", "familyName" => "Lovelace" },
          "displayName" => "Ada Lovelace",
          "emails" => [ { "value" => "ada@example.com", "type" => "work", "primary" => true } ],
          "active" => true
        }.merge(attributes.transform_keys(&:to_s)))
      end

      def amend(id, *operations)
        scim(:patch, "/Users/#{id}", body: { "schemas" => [ Scim::PATCH ], "Operations" => operations })
      end

      test "a provisioning system adds a person, and they come back as a SCIM user" do
        body = provision

        assert_response :created
        assert_equal Scim::MEDIA_TYPE, response.media_type
        assert_equal "ada@example.com", body["userName"]
        assert_equal "entra-1", body["externalId"]
        assert_equal "Ada", body.dig("name", "givenName")
        assert body["active"]
        assert_equal "#{origin_for(@tenant)}#{BASE}/Users/#{body['id']}", response.headers["Location"]

        actor = within { Actor.find_by!(uuid: body["id"]) }

        assert actor.email_verified_at.present?
        assert_equal Scopes::STANDARD, actor.scope_list
      end

      test "a person is found by userName and by externalId" do
        provision

        assert_equal 1, scim(:get, "/Users?filter=#{CGI.escape('userName eq "ADA@example.com"')}")["totalResults"]
        assert_equal 1, scim(:get, "/Users?filter=#{CGI.escape('externalId eq "entra-1"')}")["totalResults"]
        assert_equal 0, scim(:get, "/Users?filter=#{CGI.escape('externalId eq "entra-2"')}")["totalResults"]
      end

      test "a filter this server does not read is refused as one" do
        body = scim(:get, "/Users?filter=#{CGI.escape('title eq "x" or 1=1')}")

        assert_response :bad_request
        assert_equal "invalidFilter", body["scimType"]
      end

      test "pages are counted from one" do
        provision
        provision(userName: "grace@example.com", externalId: "entra-2", emails: [ { "value" => "grace@example.com" } ])

        body = scim(:get, "/Users?startIndex=2&count=1")

        assert_equal 1, body["itemsPerPage"]
        assert_operator body["totalResults"], :>=, 3
        assert_equal 2, body["startIndex"]
      end

      test "the same person twice is a conflict" do
        provision
        body = provision

        assert_response :conflict
        assert_equal "uniqueness", body["scimType"]
        assert_equal "another user already holds that userName, email or externalId", body["detail"]
      end

      test "a patch renames a person and switches them off" do
        id = provision["id"]
        within { Actor.find_by!(uuid: id).update!(password: "a-long-enough-password") }

        body = amend(id, { "op" => "Replace", "path" => "name.givenName", "value" => "Augusta" },
                     { "op" => "replace", "value" => { "active" => "False" } })

        assert_response :ok
        assert_equal "Augusta", body.dig("name", "givenName")
        refute body["active"]
        assert within { Actor.find_by!(uuid: id).suspended? }
      end

      test "a suspended person cannot sign in, and their tokens stop working" do
        id = provision["id"]
        actor = within { Actor.find_by!(uuid: id).tap { |held| held.update!(nickname: "ada", password: "password") } }
        registration = register
        granted = access_token_for(actor: actor, registration: registration)

        amend(id, { "op" => "replace", "path" => "active", "value" => false })

        refreshed = token(grant_type: "refresh_token", refresh_token: granted["refresh_token"],
                          client_id: registration["client_id"], client_secret: registration["client_secret"])
        assert_equal "invalid_grant", refreshed["error"]

        get "/userinfo", headers: { "HTTP_AUTHORIZATION" => "Bearer #{granted['access_token']}" }
        assert_response :unauthorized

        reset!
        host! host_for(@tenant)
        sign_in_as(actor)
        authorize(client_id: registration["client_id"], state: "again")

        assert_equal "access_denied", redirected["error"]
        assert within { Event.where(action: Event::ACTOR_SUSPENDED, actor: actor).exists? }
      end

      test "switching a person back on lets them in again" do
        id = provision["id"]

        amend(id, { "op" => "replace", "path" => "active", "value" => false })
        body = amend(id, { "op" => "replace", "path" => "active", "value" => true })

        assert body["active"]
        refute within { Actor.find_by!(uuid: id).suspended? }
      end

      test "a put replaces what it does not carry" do
        id = provision["id"]

        body = scim(:put, "/Users/#{id}", body: { "schemas" => [ Scim::USER ], "userName" => "ada@example.com",
                                                  "externalId" => "entra-1", "active" => true })

        assert_nil body["name"]
        assert_equal "ada@example.com", body["userName"]
      end

      test "a stale If-Match is refused" do
        id = provision["id"]

        scim(:put, "/Users/#{id}", body: { "userName" => "ada@example.com" }, headers: { "If-Match" => %(W/"1.0") })

        assert_response :precondition_failed
      end

      test "deleting a person removes them" do
        id = provision["id"]

        scim(:delete, "/Users/#{id}")

        assert_response :no_content
        scim(:get, "/Users/#{id}")
        assert_response :not_found
      end

      test "a manager's password and email are not provisioned" do
        body = amend(@manager.uuid, { "op" => "replace", "path" => "password", "value" => "taken-over-password" })

        assert_response :forbidden
        assert_equal "mutability", body["scimType"]

        amend(@manager.uuid, { "op" => "replace", "path" => "emails[type eq \"work\"].value", "value" => "evil@example.com" })
        assert_response :forbidden
      end

      test "the last manager cannot be switched off or deleted" do
        amend(@manager.uuid, { "op" => "replace", "path" => "active", "value" => false })
        assert_response :conflict

        scim(:delete, "/Users/#{@manager.uuid}")
        assert_response :conflict
      end

      test "no token, a wrong token, a revoked token and another tenant's token are all refused" do
        scim(:get, "/Users", secret: "")
        assert_response :unauthorized
        assert_match "Bearer", response.headers["WWW-Authenticate"]

        scim(:get, "/Users", secret: "wrong")
        assert_response :unauthorized

        theirs = within(other_tenant) { ProvisioningToken.issue!(label: "Elsewhere", by: nil).secret }
        scim(:get, "/Users", secret: theirs)
        assert_response :unauthorized

        within { ProvisioningToken.redeem(@secret).revoke! }
        scim(:get, "/Users")
        assert_response :unauthorized
      end

      test "an approved client signs in as itself and provisions with masks:scim" do
        client = within do
          Client.new(client_id: SecureRandom.uuid, name: "Provisioner", grant_types: [ Client::CLIENT_CREDENTIALS ],
                     allowed_scopes: Scopes::SCIM, resources: [ "#{origin_for(@tenant)}#{BASE}" ],
                     approved_at: Time.current).tap(&:issue_credentials!)
        end

        access = token(grant_type: Client::CLIENT_CREDENTIALS, client_id: client.client_id,
                       client_secret: client.secret)["access_token"]

        scim(:get, "/Users", secret: access)
        assert_response :ok

        other = token(grant_type: Client::CLIENT_CREDENTIALS, client_id: client.client_id, client_secret: client.secret,
                      scope: Scopes::SCIM)["access_token"]
        assert other
      end

      test "an access token without masks:scim is refused" do
        registration = register
        access = access_token_for(actor: @manager, registration: registration)["access_token"]
        host! host_for(@tenant)

        scim(:get, "/Users", secret: access)
        assert_response :unauthorized
      end

      test "the service provider config, resource types and schemas describe what is here" do
        config = scim(:get, "/ServiceProviderConfig")

        assert config.dig("patch", "supported")
        refute config.dig("bulk", "supported")
        assert_equal %w[User Group], scim(:get, "/ResourceTypes")["Resources"].map { |type| type["id"] }
        assert_equal Scim::USER, scim(:get, "/Schemas/#{Scim::USER}")["id"]
      end

      test "a token for one organization sees, adds, and removes only that organization's members" do
        acme = within { Organization.create!(key: "acme", name: "Acme") }
        proven(acme, "acme.example")
        outsider = create_actor(nickname: "outsider", email: "outsider@example.com")
        secret = within { ProvisioningToken.issue!(label: "Acme Entra", by: @manager, organization: acme).secret }

        listed = scim(:get, "/Users", secret: secret)

        assert_equal 0, listed["totalResults"]

        scim(:get, "/Users/#{outsider.uuid}", secret: secret)

        assert_response :not_found

        made = scim(:post, "/Users", secret: secret, body: {
          "schemas" => [ Scim::USER ], "userName" => "ada@acme.example",
          "emails" => [ { "value" => "ada@acme.example", "primary" => true } ], "active" => true
        })

        assert_response :created
        ada = within { Actor.find_by!(uuid: made["id"]) }
        assert_equal "member", within { acme.memberships.find_by!(actor: ada).role }
        assert_equal [ made["id"] ], scim(:get, "/Users", secret: secret)["Resources"].map { |user| user["id"] }

        scim(:delete, "/Users/#{made["id"]}", secret: secret)

        assert_response :no_content
        within do
          assert Actor.exists?(id: ada.id)
          refute acme.memberships.exists?(actor: ada)
          refute ada.reload.suspended?
        end
      end

      test "an organization's token cannot change someone who belongs to another organization too" do
        acme = within { Organization.create!(key: "acme", name: "Acme") }
        globex = within { Organization.create!(key: "globex", name: "Globex") }
        shared = create_actor(nickname: "shared", email: "shared@example.com")
        within do
          acme.memberships.create!(actor: shared, role: "member")
          globex.memberships.create!(actor: shared, role: "owner")
        end
        secret = within { ProvisioningToken.issue!(label: "Acme Entra", by: @manager, organization: acme).secret }

        scim(:patch, "/Users/#{shared.uuid}", secret: secret,
                                               body: { "schemas" => [ Scim::PATCH ],
                                                       "Operations" => [ { "op" => "replace", "path" => "active", "value" => false } ] })

        assert_response :forbidden
        refute within { shared.reload.suspended? }

        scim(:delete, "/Users/#{shared.uuid}", secret: secret)

        assert_response :no_content
        within do
          refute acme.memberships.exists?(actor: shared)
          assert globex.memberships.exists?(actor: shared)
        end
      end

      test "an organization's token cannot change an account its directory did not create" do
        acme = within { Organization.create!(key: "acme", name: "Acme") }
        victim = create_actor(nickname: "victim", email: "victim@example.com")
        within { acme.memberships.create!(actor: victim, role: "member") }
        secret = within { ProvisioningToken.issue!(label: "Acme Entra", by: @manager, organization: acme).secret }

        scim(:patch, "/Users/#{victim.uuid}", secret: secret,
                                               body: { "schemas" => [ Scim::PATCH ],
                                                       "Operations" => [ { "op" => "replace", "path" => "password", "value" => "taken-over-1" } ] })

        assert_response :forbidden
        refute within { victim.reload.authenticate("taken-over-1") }

        scim(:delete, "/Users/#{victim.uuid}", secret: secret)

        assert_response :no_content
        assert within { Actor.exists?(victim.id) }
      end

      test "an organization's token changes the accounts its directory created" do
        acme = within { Organization.create!(key: "acme", name: "Acme") }
        proven(acme, "acme.example")
        secret = within { ProvisioningToken.issue!(label: "Acme Entra", by: @manager, organization: acme).secret }

        made = scim(:post, "/Users", secret: secret, body: {
          "schemas" => [ Scim::USER ], "userName" => "grace@acme.example",
          "emails" => [ { "value" => "grace@acme.example", "primary" => true } ], "active" => true
        })

        scim(:patch, "/Users/#{made["id"]}", secret: secret,
                                               body: { "schemas" => [ Scim::PATCH ],
                                                       "Operations" => [ { "op" => "replace", "path" => "active", "value" => false } ] })

        assert_response :success
        assert within { Actor.find_by!(uuid: made["id"]).suspended? }
      end

      def acme_token(acme)
        within { ProvisioningToken.issue!(label: "Acme Entra", by: @manager, organization: acme).secret }
      end

      def proven(acme, domain)
        within do
          provider = Provider.create!(key: "acme-idp", name: "Acme IdP", organization: acme, issuer: "https://idp.acme.example",
                                      authorization_url: "https://idp.acme.example/authorize", token_url: "https://idp.acme.example/token",
                                      jwks_uri: "https://idp.acme.example/jwks", client_id: "c", client_secret: "s")
          DomainClaim.create!(domain: domain, provider: provider).update_columns(verified_at: Time.current)
        end
      end

      def join_acme(secret, email)
        scim(:post, "/Users", secret: secret, body: {
          "schemas" => [ Scim::USER ], "userName" => email,
          "emails" => [ { "value" => email, "primary" => true } ], "active" => true
        })
      end

      test "an organization's token without a proven domain sets no address, whether or not someone holds it" do
        acme = within { Organization.create!(key: "acme", name: "Acme") }
        create_actor(nickname: "ceo", email: "ceo@othercorp.example")
        secret = acme_token(acme)

        held = join_acme(secret, "ceo@othercorp.example")
        held_status = response.status
        free = join_acme(secret, "cfo@othercorp.example")

        assert_equal 400, held_status
        assert_response :bad_request
        assert_equal held, free
        assert_equal "invalidValue", free["scimType"]
        refute within { Actor.exists?(email: "cfo@othercorp.example") }

        made = scim(:post, "/Users", secret: secret, body: { "schemas" => [ Scim::USER ], "userName" => "grace", "active" => true })

        assert_response :created
        assert_nil within { Actor.find_by!(uuid: made["id"]).email }
      end

      test "a foreign address someone holds and one nobody holds are refused alike, before anything is looked up" do
        acme = within { Organization.create!(key: "acme", name: "Acme") }
        proven(acme, "acme.example")
        create_actor(nickname: "ceo", email: "ceo@othercorp.example")
        secret = acme_token(acme)
        made = join_acme(secret, "ada@acme.example")

        answers = %w[ceo@othercorp.example cfo@othercorp.example].map do |email|
          body = scim(:patch, "/Users/#{made["id"]}", secret: secret,
                                                      body: { "schemas" => [ Scim::PATCH ],
                                                              "Operations" => [ { "op" => "replace", "path" => "userName", "value" => email } ] })

          [ response.status, body ]
        end

        assert_equal 400, answers.first.first
        assert_equal answers.first, answers.last
      end

      test "an organization's token verifies addresses at its proven domains and refuses any other" do
        acme = within { Organization.create!(key: "acme", name: "Acme") }
        proven(acme, "acme.example")
        secret = acme_token(acme)

        made = join_acme(secret, "ada@acme.example")

        assert_response :created
        assert within { Actor.find_by!(uuid: made["id"]).email_verified_at.present? }

        refused = join_acme(secret, "ceo@othercorp.example")

        assert_response :bad_request
        assert_equal "invalidValue", refused["scimType"]
        refute within { Actor.exists?(email: "ceo@othercorp.example") }

        scim(:patch, "/Users/#{made["id"]}", secret: secret,
                                               body: { "schemas" => [ Scim::PATCH ],
                                                       "Operations" => [ { "op" => "replace", "path" => "emails",
                                                                           "value" => [ { "value" => "ceo@othercorp.example", "primary" => true } ] } ] })

        assert_response :bad_request
        assert_equal "ada@acme.example", within { Actor.find_by!(uuid: made["id"]).email }
      end

      test "an organization's token learns nothing about who else holds an address" do
        acme = within { Organization.create!(key: "acme", name: "Acme") }
        proven(acme, "acme.example")
        create_actor(nickname: "ceo", email: "ceo@acme.example")

        taken = join_acme(acme_token(acme), "ceo@acme.example")

        assert_response :conflict
        assert_equal "uniqueness", taken["scimType"]
        assert_equal "another user already holds that userName, email or externalId", taken["detail"]
      end

      test "an invitation another organization has not had accepted does not block deprovisioning" do
        acme = within { Organization.create!(key: "acme", name: "Acme") }
        proven(acme, "acme.example")
        globex = within { Organization.create!(key: "globex", name: "Globex") }
        secret = acme_token(acme)
        made = join_acme(secret, "grace@acme.example")
        within { globex.memberships.create!(actor: Actor.find_by!(uuid: made["id"]), role: "member", pending: true) }

        scim(:patch, "/Users/#{made["id"]}", secret: secret,
                                               body: { "schemas" => [ Scim::PATCH ],
                                                       "Operations" => [ { "op" => "replace", "path" => "active", "value" => false } ] })

        assert_response :success
        assert within { Actor.find_by!(uuid: made["id"]).suspended? }
      end
      def directed(secret, user_name, external_id)
        scim(:post, "/Users", secret: secret, body: {
          "schemas" => [ Scim::USER ], "userName" => user_name, "externalId" => external_id, "active" => true
        })
      end

      test "two organizations' directories use the same externalId without meeting" do
        acme = within { Organization.create!(key: "acme", name: "Acme") }
        globex = within { Organization.create!(key: "globex", name: "Globex") }
        acme_secret = acme_token(acme)
        globex_secret = within { ProvisioningToken.issue!(label: "Globex Okta", by: @manager, organization: globex).secret }

        ada = directed(acme_secret, "ada", "okta-1")

        assert_response :created
        assert_equal "okta-1", ada["externalId"]

        grace = directed(globex_secret, "grace", "okta-1")

        assert_response :created
        assert_equal "okta-1", grace["externalId"]

        found = scim(:get, "/Users?filter=#{CGI.escape('externalId eq "okta-1"')}", secret: acme_secret)

        assert_equal [ ada["id"] ], found["Resources"].map { |user| user["id"] }
        assert_equal "okta-1", scim(:get, "/Users/#{grace["id"]}", secret: globex_secret)["externalId"]
        assert_nil within { Actor.find_by!(uuid: ada["id"]).external_id }
      end

      test "one directory's externalId stays unique within its organization, and the conflict says no more than any other" do
        acme = within { Organization.create!(key: "acme", name: "Acme") }
        secret = acme_token(acme)

        directed(secret, "ada", "okta-1")
        taken = directed(secret, "grace", "okta-1")

        assert_response :conflict
        assert_equal "uniqueness", taken["scimType"]
        assert_equal "another user already holds that userName, email or externalId", taken["detail"]
        refute within { Actor.exists?(nickname: "grace") }

        create_actor(nickname: "outsider")
        elsewhere = directed(secret, "outsider", "okta-2")

        assert_response :conflict
        assert_equal taken.except("status"), elsewhere.except("status")
      end

      test "a directory's externalId is replaced and cleared with the rest of the user" do
        acme = within { Organization.create!(key: "acme", name: "Acme") }
        secret = acme_token(acme)
        made = directed(secret, "ada", "okta-1")

        amended = scim(:patch, "/Users/#{made["id"]}", secret: secret,
                                                       body: { "schemas" => [ Scim::PATCH ],
                                                               "Operations" => [ { "op" => "replace", "path" => "externalId", "value" => "okta-9" } ] })

        assert_equal "okta-9", amended["externalId"]

        replaced = scim(:put, "/Users/#{made["id"]}", secret: secret, body: { "schemas" => [ Scim::USER ], "userName" => "ada" })

        assert_nil replaced["externalId"]
        assert_nil within { acme.memberships.sole.external_id }
      end
    end
  end
end
