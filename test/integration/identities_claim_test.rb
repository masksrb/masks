require "test_helper"

class IdentitiesClaimTest < ActionDispatch::IntegrationTest
  setup do
    host! host_for(@tenant)

    @actor = create_actor(@tenant, nickname: "ada", email: "ada@acme.test")

    within(@tenant) do
      @provider = Provider.create!(
        key: "google", name: "Google", issuer: "https://accounts.google.com",
        authorization_url: "https://accounts.google.com/o/oauth2/v2/auth",
        token_url: "https://oauth2.googleapis.com/token", client_id: "upstream"
      )

      Connection.record!(
        provider: @provider, actor: @actor,
        identity: { "sub" => "google-123", "email" => "ada@gmail.test", "email_verified" => true }
      )
    end
  end

  def client!(**attributes)
    create_client(@tenant, allowed_scopes: Scopes.join(Scopes::STANDARD), **attributes)
  end

  def userinfo_for(client, scope:)
    sign_in_as(@actor)
    authorize(client_id: client.client_id, scope: scope)
    consent! if awaiting_consent?

    granted = token(
      grant_type: "authorization_code", code: code_from, redirect_uri: OidcFlow::REDIRECT_URI,
      code_verifier: verifier, client_id: client.client_id
    )

    get "/userinfo", headers: { "HTTP_AUTHORIZATION" => "Bearer #{granted['access_token']}" }

    JSON.parse(response.body)
  end

  test "the identities scope names the accounts elsewhere somebody signs in with" do
    claims = userinfo_for(client!, scope: "openid identities")

    assert_equal [ { "provider" => "google", "protocol" => "oidc", "sub" => "google-123", "email" => "ada@gmail.test" } ],
                 claims["identities"]
  end

  test "without the scope nothing about other accounts is said" do
    claims = userinfo_for(client!, scope: "openid email")

    assert_nil claims["identities"]
  end

  test "a pairwise client is not handed the subjects that would let it correlate somebody" do
    client = client!(subject_type: "pairwise")

    claims = userinfo_for(client, scope: "openid identities")

    assert_nil claims["identities"]
  end

  test "a disconnected account is not named" do
    within(@tenant) { Connection.live.find_each(&:revoke!) }

    claims = userinfo_for(client!, scope: "openid identities")

    assert_equal [], claims["identities"]
  end

  test "an unconfirmed address is left out of the identity" do
    within(@tenant) { Connection.live.sole.update!(email_verified: false) }

    claims = userinfo_for(client!, scope: "openid identities")

    assert_nil claims["identities"].first["email"]
  end

  test "discovery offers the scope and the claim" do
    get "/.well-known/openid-configuration"

    body = JSON.parse(response.body)

    assert_includes body["scopes_supported"], "identities"
    assert_includes body["claims_supported"], "identities"
  end

  test "the consent screen says what the scope reveals" do
    sign_in_as(@actor)
    authorize(client_id: client!.client_id, scope: "openid identities")

    assert_match "The accounts elsewhere you sign in with", response.body
  end
end
