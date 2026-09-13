require "test_helper"

class RevocationTest < ActionDispatch::IntegrationTest
  EXCHANGE = Exchange::GRANT_TYPE

  setup do
    @actor = create_actor(email: "owner@probe.example.com", name: "Owner")
    @registration = register(grant_types: [ "authorization_code", "refresh_token", EXCHANGE ])
    host! host_for(@tenant)
  end

  def revoke(value, registration: @registration, **params)
    post "/revoke", params: {
      token: value,
      client_id: registration["client_id"],
      client_secret: registration["client_secret"]
    }.merge(params)

    response
  end

  def exchange(subject, registration: @registration)
    token(
      grant_type: EXCHANGE, subject_token: subject,
      subject_token_type: Exchange::ACCESS_TOKEN,
      client_id: registration["client_id"],
      client_secret: registration["client_secret"]
    )
  end

  def live?(access)
    get "/userinfo", headers: { "HTTP_AUTHORIZATION" => "Bearer #{access}" }
    response.successful?
  end

  test "revoking a root revokes its children and theirs" do
    root = access_token_for(actor: @actor, registration: @registration)["access_token"]
    child = exchange(root)["access_token"]
    grandchild = exchange(child)["access_token"]

    assert live?(root)
    assert live?(child)
    assert live?(grandchild)

    revoke(root)
    assert_response :ok

    assert_not live?(root)
    assert_not live?(child)
    assert_not live?(grandchild)
  end

  test "a revoked token cannot be exchanged" do
    root = access_token_for(actor: @actor, registration: @registration)["access_token"]
    revoke(root)

    assert_equal "invalid_grant", exchange(root)["error"]
  end

  test "revoking a child leaves its parent alone" do
    root = access_token_for(actor: @actor, registration: @registration)["access_token"]
    child = exchange(root)["access_token"]

    revoke(child)

    assert live?(root)
    assert_not live?(child)
  end

  test "one client cannot revoke another's token" do
    other = register(client_name: "Other")
    root = access_token_for(actor: @actor, registration: @registration)["access_token"]

    revoke(root, registration: other)
    assert_response :ok

    assert live?(root)
  end

  test "revocation answers ok for a token it does not recognise" do
    revoke("nothing-like-a-token")

    assert_response :ok
  end

  test "revocation requires client authentication" do
    root = access_token_for(actor: @actor, registration: @registration)["access_token"]

    post "/revoke", params: {
      token: root,
      client_id: @registration["client_id"],
      client_secret: "not-the-secret"
    }

    assert_response :unauthorized
    assert_equal "invalid_client", JSON.parse(response.body)["error"]
  end

  test "a refresh token is revoked by value" do
    issued = access_token_for(actor: @actor, registration: @registration)

    revoke(issued["refresh_token"], token_type_hint: "refresh_token")
    assert_response :ok

    body = token(
      grant_type: "refresh_token", refresh_token: issued["refresh_token"],
      client_id: @registration["client_id"], client_secret: @registration["client_secret"]
    )

    assert_equal "invalid_grant", body["error"]
  end

  test "revoking a refresh token ends the access token issued beside it" do
    issued = access_token_for(actor: @actor, registration: @registration)

    assert live?(issued["access_token"])

    revoke(issued["refresh_token"], token_type_hint: "refresh_token")

    assert_not live?(issued["access_token"])
  end

  test "revoking a rotated refresh token ends every access token its grant issued" do
    issued = access_token_for(actor: @actor, registration: @registration)
    rotated = token(
      grant_type: "refresh_token", refresh_token: issued["refresh_token"],
      client_id: @registration["client_id"], client_secret: @registration["client_secret"]
    )
    child = exchange(rotated["access_token"])["access_token"]

    revoke(rotated["refresh_token"])

    assert_not live?(issued["access_token"])
    assert_not live?(rotated["access_token"])
    assert_not live?(child)
  end

  test "revoking an access token leaves its refresh token alone" do
    issued = access_token_for(actor: @actor, registration: @registration)

    revoke(issued["access_token"])

    body = token(
      grant_type: "refresh_token", refresh_token: issued["refresh_token"],
      client_id: @registration["client_id"], client_secret: @registration["client_secret"]
    )

    assert body["access_token"].present?
  end
end
