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

  test "profile releases the whole standard claim set it has values for" do
    Tenant.switch(@tenant) do
      @actor.update!(
        given_name: "Given", family_name: "Family", middle_name: "Middle",
        profile_url: "https://example.com/p", picture_url: "https://example.com/p.png",
        website_url: "https://example.com", gender: "unspecified",
        birthdate: "1970-01-01", zoneinfo: "Etc/UTC", locale: "en"
      )
    end

    claims = userinfo(access_token_for(actor: @actor, registration: @registration)["access_token"])

    %w[name given_name family_name middle_name nickname preferred_username
       profile picture website gender birthdate zoneinfo locale updated_at].each do |claim|
      assert claims.key?(claim), "userinfo is missing #{claim}"
    end
  end

  test "the claims parameter releases a claim the scope did not" do
    sign_in_as(@actor)
    authorize(
      client_id: @registration["client_id"], scope: "openid",
      claims: { userinfo: { name: { essential: true } } }.to_json
    )
    consent! if awaiting_consent?

    granted = token(
      grant_type: "authorization_code", code: code_from,
      redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier,
      client_id: @registration["client_id"],
      client_secret: @registration["client_secret"]
    )

    claims = userinfo(granted["access_token"])

    assert_equal @actor.name, claims["name"]
    assert_nil claims["email"]
  end

  def introspect(value)
    post "/introspect",
         params: URI.encode_www_form(
           token: value,
           client_id: @registration["client_id"],
           client_secret: @registration["client_secret"]
         ),
         headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }

    JSON.parse(response.body)
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

  test "a replay takes the whole family down with it, not just the token replayed" do
    issued = access_token_for(actor: @actor, registration: @registration)
    rotated = refresh(issued["refresh_token"])

    assert_equal "invalid_grant", refresh(issued["refresh_token"])["error"]

    assert_equal "invalid_grant", refresh(rotated["refresh_token"])["error"],
                 "the branch the thief did not touch has to die too"

    assert_not introspect(rotated["access_token"])["active"],
               "an access token minted from the family is no longer live"
    assert_not introspect(issued["access_token"])["active"],
               "the first access token of the family is no longer live either"
  end

  test "a replay is written down, with what it cost" do
    issued = access_token_for(actor: @actor, registration: @registration)

    refresh(issued["refresh_token"])
    refresh(issued["refresh_token"])

    replay = Tenant.switch(@tenant) { Event.where(action: Event::REFRESH_REUSED).first }

    assert_not_nil replay
    assert_equal @actor.id, replay.actor_id
    assert replay.details["revoked"].to_i.positive?
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
