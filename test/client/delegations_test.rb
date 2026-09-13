require_relative "test_helper"
require "masks/client/delegations/fake"

class DelegationsTest < ClientTest
  def delegations
    Masks::Client.delegations(issuer.url, client_id: "uris", client_secret: "shh", redirect_uri: "https://app.test/connect/callback")
  end

  def granted(provider: "google")
    { "access_token" => "masks-access", "token_type" => "Bearer", "expires_in" => 3600, "refresh_token" => "masks-refresh",
      "delegations" => [ { "connection" => "c-1", "provider" => provider, "provider_name" => "Google",
                           "label" => "grace@example.com", "subject" => "actor-1" } ] }
  end

  def test_connecting_asks_for_the_delegation_scope_with_pkce
    started = delegations.start(provider: "google", max_age: 900)
    query = URI.decode_www_form(URI.parse(started["url"]).query).to_h

    assert_equal "openid offline_access masks:delegate:google", query["scope"]
    assert_equal "S256", query["code_challenge_method"]
    assert_equal started["state"], query["state"]
    assert_equal "900", query["max_age"]
    assert_equal "google", started["provider"]
  end

  def test_finishing_holds_the_connection_and_a_secret
    issuer.override("/token", granted)
    started = delegations.start(provider: "google")

    held = delegations.finish(params: { "code" => "abc", "state" => started["state"] }, started: started)

    assert_equal "c-1", held.connection
    assert_equal "google", held.provider
    assert_equal "actor-1", held.subject
    assert_equal "masks-refresh", held.secret

    sent = issuer.last("/token")[:body]

    assert_equal "authorization_code", sent["grant_type"]
    assert_equal started["verifier"], sent["code_verifier"]
    assert_equal "shh", sent["client_secret"]
  end

  def test_a_state_that_does_not_match_is_refused_before_anything_is_redeemed
    started = delegations.start(provider: "google")

    error = assert_raises(Masks::Client::Delegations::Refused) do
      delegations.finish(params: { "code" => "abc", "state" => "forged" }, started: started)
    end

    assert_equal "invalid_state", error.code
    assert_equal 0, issuer.count("/token")
  end

  def test_an_error_on_the_callback_is_a_refusal
    started = delegations.start(provider: "google")

    error = assert_raises(Masks::Client::Delegations::Refused) do
      delegations.finish(params: { "error" => "login_required", "state" => started["state"] }, started: started)
    end

    assert error.signed_in_again?
  end

  def test_finishing_without_a_delegation_for_that_provider_is_refused
    issuer.override("/token", granted(provider: "microsoft"))
    started = delegations.start(provider: "google")

    assert_raises(Masks::Client::Delegations::Refused) do
      delegations.finish(params: { "code" => "abc", "state" => started["state"] }, started: started)
    end
  end

  def test_a_token_is_a_refresh_then_an_exchange_and_the_secret_rotates
    issuer.override("/token", lambda do |body|
      if body["grant_type"] == "refresh_token"
        { "access_token" => "masks-access-2", "refresh_token" => "masks-refresh-2", "expires_in" => 3600 }
      else
        { "access_token" => "ya29.upstream", "issued_token_type" => Masks::Client::Delegations::UPSTREAM_ACCESS_TOKEN,
          "token_type" => "Bearer", "expires_in" => 1800, "scope" => "drive.readonly" }
      end
    end)

    upstream = delegations.token("masks-refresh", connection: "c-1")

    assert_equal "ya29.upstream", upstream.access_token
    assert_equal "masks-refresh-2", upstream.secret
    assert_in_delta Time.now.to_i + 1800, upstream.expires_at, 5
    refute upstream.expired?

    exchanged = issuer.last("/token")[:body]

    assert_equal Masks::Client::Tokens::EXCHANGE, exchanged["grant_type"]
    assert_equal "masks-access-2", exchanged["subject_token"]
    assert_equal "c-1", exchanged["audience"]
    assert_equal Masks::Client::Delegations::UPSTREAM_ACCESS_TOKEN, exchanged["requested_token_type"]
  end

  def test_a_revoked_delegation_is_refused_and_still_hands_back_the_rotated_secret
    issuer.override("/token", lambda do |body|
      if body["grant_type"] == "refresh_token"
        { "access_token" => "masks-access-2", "refresh_token" => "masks-refresh-2" }
      else
        [ 400, { "error" => "invalid_grant", "error_description" => "not let this client use that connection" } ]
      end
    end)

    error = assert_raises(Masks::Client::Delegations::Refused) { delegations.token("masks-refresh", connection: "c-1") }

    assert_equal "invalid_grant", error.code
    assert_equal "masks-refresh-2", error.secret
  end

  def test_a_provider_that_does_not_answer_is_worth_retrying
    issuer.override("/token", lambda do |body|
      if body["grant_type"] == "refresh_token"
        { "access_token" => "masks-access-2", "refresh_token" => "masks-refresh-2" }
      else
        [ 503, { "error" => "temporarily_unavailable", "error_description" => "Google did not answer a refresh" } ]
      end
    end)

    error = assert_raises(Masks::Client::Delegations::Unavailable) { delegations.token("masks-refresh", connection: "c-1") }

    assert_equal "masks-refresh-2", error.secret
  end

  def test_masks_itself_being_unreachable_is_worth_retrying
    offline = Masks::Client::Delegations.new(issuer: issuer.url, client_id: "uris", client_secret: "shh", redirect_uri: "https://app.test/cb")
    offline.issuer.discovery
    issuer.stop

    assert_raises(Masks::Client::Delegations::Unavailable) { offline.token("masks-refresh", connection: "c-1") }
  end

  def test_the_fake_connects_releases_rotates_and_refuses
    fake = Masks::Client::Delegations::Fake.new
    started = fake.start(provider: "notion")
    held = fake.finish(params: fake.approve(started, subject: "actor-9", connection: "c-9"), started: started)

    assert_equal "c-9", held.connection
    assert_equal "actor-9", held.subject

    upstream = fake.token(held.secret, connection: held.connection)

    assert_equal "notion-access-1", upstream.access_token
    refute_equal held.secret, upstream.secret
    assert_raises(Masks::Client::Delegations::Refused) { fake.token(held.secret, connection: held.connection) }

    fake.unavailable(held.connection)
    assert_raises(Masks::Client::Delegations::Unavailable) { fake.token(upstream.secret, connection: held.connection) }

    fake.unavailable(held.connection, now: false)
    fake.revoke(held.connection)
    refused = assert_raises(Masks::Client::Delegations::Refused) { fake.token(upstream.secret, connection: held.connection) }

    assert_equal "invalid_grant", refused.code
    assert_equal 1, fake.releases
  end

  def test_the_fake_refuses_a_declined_connection
    fake = Masks::Client::Delegations::Fake.new
    started = fake.start(provider: "google")

    assert_raises(Masks::Client::Delegations::Refused) { fake.finish(params: fake.deny(started), started: started) }
  end
end
