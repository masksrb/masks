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
    assert_equal "User", scim(:get, "/ResourceTypes")["Resources"].first["id"]
    assert_equal Scim::USER, scim(:get, "/Schemas/#{Scim::USER}")["id"]
  end
end
