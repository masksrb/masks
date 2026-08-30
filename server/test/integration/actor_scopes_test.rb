require "test_helper"

class ActorScopesTest < ActionDispatch::IntegrationTest
  REQUESTED = "openid profile email things:read admin".freeze

  def token_for(actor, registration, scope: REQUESTED)
    sign_in_as(actor)
    authorize(client_id: registration["client_id"], scope: scope)
    consent! if awaiting_consent?

    token(
      grant_type: "authorization_code",
      code: code_from,
      redirect_uri: OidcFlow::REDIRECT_URI,
      code_verifier: verifier,
      client_id: registration["client_id"],
      client_secret: registration["client_secret"]
    )
  end

  def registration_for(scope: REQUESTED)
    register(@tenant, scope: scope)
  end

  test "a custom scope the client and the actor both hold reaches the token" do
    actor = create_actor(@tenant, scopes: "openid profile email things:read")

    granted = token_for(actor, registration_for)

    assert_includes granted["scope"].split, "things:read"
    assert_includes claims_in(granted["access_token"])["scope"].split, "things:read"
  end

  test "a scope the client requests but the actor does not hold is withheld" do
    actor = create_actor(@tenant, scopes: "openid profile email things:read")

    granted = token_for(actor, registration_for)

    refute_includes granted["scope"].split, "admin",
                    "an open registration must not be able to name its own authority"
    refute_includes claims_in(granted["access_token"])["scope"].split, "admin"
  end

  test "a scope the client never registered refuses the whole request" do
    actor = create_actor(@tenant, scopes: "openid profile email admin")
    registration = registration_for(scope: "openid profile email")

    sign_in_as(actor)
    authorize(client_id: registration["client_id"], scope: REQUESTED)

    assert_equal "invalid_scope", redirected["error"]
    assert_includes redirected["error_description"], "admin"
  end

  test "the client bound is a refusal and the actor bound is a narrowing" do
    actor = create_actor(@tenant, scopes: "openid profile email things:read")

    granted = token_for(actor, registration_for)

    assert_equal %w[email openid profile things:read], granted["scope"].split.sort,
                 "an actor short of a scope the client may request signs in without it, " \
                 "rather than being unable to sign in at all"
  end

  test "an actor holding the scope receives it" do
    actor = create_actor(@tenant, scopes: "openid profile email admin")

    granted = token_for(actor, registration_for)

    assert_includes granted["scope"].split, "admin"
  end

  test "an actor with no scopes recorded holds the ones masks itself defines, and no others" do
    actor = create_actor(@tenant)

    granted = token_for(actor, registration_for)

    assert_equal %w[email openid profile], granted["scope"].split.sort,
                 "identity scopes are the actor's own by default; app authority is not"
  end

  test "a blank actor still reaches offline_access, so a refresh token is issued" do
    actor = create_actor(@tenant)
    registration = registration_for(scope: "openid profile email offline_access")

    granted = token_for(actor, registration, scope: "openid profile email offline_access")

    assert_includes granted["scope"].split, "offline_access"
    assert granted["refresh_token"].present?
  end

  test "the id token is still issued when custom scopes are in play" do
    actor = create_actor(@tenant, scopes: "openid profile email things:read")

    granted = token_for(actor, registration_for)

    assert granted["id_token"].present?
    assert_equal actor.uuid, claims_in(granted["id_token"])["sub"]
  end
end
