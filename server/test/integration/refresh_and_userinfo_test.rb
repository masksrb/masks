require "test_helper"

class RefreshAndUserinfoTest < ActionDispatch::IntegrationTest
  setup do
    @actor = create_actor(email: "owner@probe.example.com", name: "Owner")
    @registration = register
    host! host_for(@tenant)
  end

  def refresh(token_value, **params)
    token(
      grant_type: "refresh_token", refresh_token: token_value,
      client_id: @registration["client_id"], client_secret: @registration["client_secret"],
      **params
    )
  end

  def userinfo(access)
    get "/userinfo", headers: { "HTTP_AUTHORIZATION" => "Bearer #{access}" }
    JSON.parse(response.body)
  end

  test "a refresh rotates the token it was presented with" do
    issued = access_token_for(actor: @actor, registration: @registration)
    rotated = refresh(issued["refresh_token"])

    assert rotated["access_token"].present?
    assert rotated["refresh_token"].present?
    assert_not_equal issued["refresh_token"], rotated["refresh_token"]
  end

  test "a replayed refresh token is refused" do
    issued = access_token_for(actor: @actor, registration: @registration)

    assert refresh(issued["refresh_token"])["access_token"].present?
    assert_equal "invalid_grant", refresh(issued["refresh_token"])["error"]
  end

  test "a refresh may narrow scope but not widen it" do
    issued = access_token_for(actor: @actor, registration: @registration)

    narrowed = refresh(issued["refresh_token"], scope: "openid")
    assert_equal "openid", narrowed["scope"]

    widened = refresh(narrowed["refresh_token"], scope: "openid profile email")
    assert_equal "openid", widened["scope"]
  end

  test "a refresh token belongs to the client it was issued to" do
    other = register(client_name: "Other")
    issued = access_token_for(actor: @actor, registration: @registration)

    body = token(
      grant_type: "refresh_token", refresh_token: issued["refresh_token"],
      client_id: other["client_id"], client_secret: other["client_secret"]
    )

    assert_equal "invalid_grant", body["error"]
  end

  test "userinfo releases a claim only when its scope was granted" do
    issued = access_token_for(actor: @actor, registration: @registration)
    claims = userinfo(issued["access_token"])

    assert_equal @actor.uuid, claims["sub"]
    assert_equal @actor.nickname, claims["preferred_username"]
    assert_equal @actor.email, claims["email"]
  end

  test "userinfo withholds the name and address a narrower token did not ask for" do
    issued = access_token_for(actor: @actor, registration: @registration)
    narrowed = refresh(issued["refresh_token"], scope: "openid")
    claims = userinfo(narrowed["access_token"])

    assert_equal @actor.uuid, claims["sub"]
    assert_nil claims["preferred_username"]
    assert_nil claims["email"]
  end

  test "userinfo challenges a request carrying no token" do
    get "/userinfo"

    assert_response :unauthorized
    assert_match "Bearer", response.headers["WWW-Authenticate"]
  end

  test "userinfo refuses a token this tenant did not sign" do
    issued = access_token_for(actor: @actor, registration: @registration)

    host! host_for(@other)
    get "/userinfo", headers: { "HTTP_AUTHORIZATION" => "Bearer #{issued['access_token']}" }

    assert_response :unauthorized
  end

  test "userinfo refuses a revoked token" do
    issued = access_token_for(actor: @actor, registration: @registration)

    post "/revoke", params: {
      token: issued["refresh_token"], token_type_hint: "refresh_token",
      client_id: @registration["client_id"], client_secret: @registration["client_secret"]
    }
    assert_response :ok

    assert_equal "invalid_grant", refresh(issued["refresh_token"])["error"]
  end
end
