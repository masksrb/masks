require "test_helper"
require_relative "../support/upstream"

class SingleSignOnTest < ActionDispatch::IntegrationTest
  include Federated

  test "a confirmed address asks the account that holds it to prove itself first" do
    create_provider
    actor = create_actor(@tenant, nickname: "ada", email: "ada@acme.test")
    within(@tenant) { actor.update!(email_verified_at: Time.current) }

    finish_sso(sub: "upstream-1", email: "ada@acme.test")

    assert_nil signed_in_actor
    assert_nil within(@tenant) { Connection.find_by(subject: "upstream-1") }

    get "/login"
    assert_equal "first-factor", auth_data["prompt"]

    prove

    assert_equal actor.id, signed_in_actor&.id

    within(@tenant) do
      connection = Connection.live.find_by(subject: "upstream-1")

      assert_equal actor.id, connection.actor_id
      assert connection.signed_in_at.present?
      assert connection.email_verified
    end
  end

  test "a second sign-in reuses the connection rather than matching on email again" do
    create_provider
    actor = create_actor(@tenant, nickname: "ada", email: "ada@acme.test")
    within(@tenant) { actor.update!(email_verified_at: Time.current) }

    finish_sso(sub: "upstream-1", email: "ada@acme.test")
    prove
    within(@tenant) { actor.update!(email: "moved@acme.test") }

    reset!
    host! host_for(@tenant)
    finish_sso(sub: "upstream-1", email: "ada@acme.test")

    assert_equal actor.id, signed_in_actor&.id
    assert_equal 1, within(@tenant) { Connection.live.count }
  end

  test "a revoked connection is taken up again once the account proves itself" do
    create_provider
    actor = create_actor(@tenant, nickname: "ada", email: "ada@acme.test")
    within(@tenant) { actor.update!(email_verified_at: Time.current) }

    finish_sso(sub: "upstream-1", email: "ada@acme.test")
    prove

    within(@tenant) do
      Connection.find_by(subject: "upstream-1").revoke!(upstream: false)
      Session.live.find_each(&:revoke!)
    end

    reset!
    host! host_for(@tenant)
    finish_sso(sub: "upstream-1", email: "ada@acme.test")

    assert_nil signed_in_actor

    prove

    assert_equal actor.id, signed_in_actor&.id
    assert_equal 1, within(@tenant) { Connection.count }
    assert within(@tenant) { Connection.find_by(subject: "upstream-1").revoked_at.nil? }
  end

  test "an unconfirmed address never reaches the account that holds it" do
    create_provider(provisions: true)
    actor = create_actor(@tenant, nickname: "ada", email: "ada@acme.test")
    within(@tenant) { actor.update!(email_verified_at: Time.current) }

    finish_sso(sub: "intruder", email: "ada@acme.test", verified: false)

    assert_nil signed_in_actor
    assert_equal 1, within(@tenant) { Actor.count }
  end

  test "an empty instance is set up locally, never over sso" do
    create_provider(provisions: true)

    finish_sso(sub: "upstream-0", email: "first@acme.test")

    assert_nil signed_in_actor
    assert_equal 0, within(@tenant) { Actor.count }

    get "/login"

    assert_equal "setup", auth_data["prompt"]
    assert_nil auth_data["providers"]
  end

  test "a provider that does not provision refuses somebody with no account" do
    create_provider
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    finish_sso(sub: "upstream-9", email: "nobody@acme.test")

    assert_nil signed_in_actor
    assert_equal 1, within(@tenant) { Actor.count }
    assert within(@tenant) { Event.exists?(action: Event::CONNECTION_REFUSED) }
  end

  test "a provider that provisions creates the account and signs it in" do
    create_provider(provisions: true, email_domains: "acme.test")
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    finish_sso(sub: "upstream-2", email: "grace@acme.test", name: "Grace Hopper")

    actor = signed_in_actor

    assert actor, refusals.join("; ")
    assert_equal "grace", actor.nickname
    assert_equal "grace@acme.test", actor.email
    assert_equal "Grace Hopper", actor.name
    assert actor.email_verified_at.present?
    assert actor.activated?
    assert_equal Scopes::STANDARD.sort, actor.scope_list.sort
    assert within(@tenant) { Event.exists?(action: Event::ACTOR_PROVISIONED) }
  end

  test "a provisioned nickname steps aside when the obvious one is taken" do
    create_provider(provisions: true, email_domains: "acme.test")
    create_actor(@tenant, nickname: "grace", email: "someone@elsewhere.test")

    finish_sso(sub: "upstream-3", email: "grace@acme.test")

    assert_equal "grace2", signed_in_actor&.nickname
  end

  test "an email domain outside the list is refused" do
    create_provider(provisions: true, email_domains: "acme.test")
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    finish_sso(sub: "upstream-4", email: "someone@evil.test")

    assert_nil signed_in_actor
    assert_equal 1, within(@tenant) { Actor.count }
  end

  test "an identity carrying no address is refused when the list is set" do
    create_provider(provisions: true, email_domains: "acme.test")
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    finish_sso(sub: "upstream-11", email: nil, verified: false)

    assert_nil signed_in_actor
    assert_equal 1, within(@tenant) { Actor.count }
  end

  test "an unconfirmed address inside the list is refused" do
    create_provider(provisions: true, email_domains: "acme.test")
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    finish_sso(sub: "upstream-12", email: "someone@acme.test", verified: false)

    assert_nil signed_in_actor
    assert_equal 1, within(@tenant) { Actor.count }
  end

  test "a provider that answers for no domain provisions nobody" do
    create_provider(provisions: true)
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    finish_sso(sub: "upstream-13", email: "hopeful@acme.test")

    assert_nil signed_in_actor
    assert_equal 1, within(@tenant) { Actor.count }
  end

  test "a provider that confirms no address provisions an account without one" do
    create_provider(provisions: true)
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    finish_sso(sub: "upstream-13b", email: nil, verified: false)

    actor = signed_in_actor

    assert actor, refusals.join("; ")
    assert_nil actor.email
    assert_nil actor.email_verified_at
  end

  test "an invitation is taken up only by a provider that answers for its address" do
    create_provider(provisions: true)
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")
    within(@tenant) { Actor.create!(nickname: "ada", email: "ada@acme.test") }

    finish_sso(sub: "stranger", email: "ada@acme.test")

    assert_nil signed_in_actor
    assert_match "does not answer for acme.test", refusals.join("; ")
  end

  test "a confirmed address stays out of an active account that never confirmed it" do
    create_provider
    create_actor(@tenant, nickname: "ada", email: "ada@acme.test")

    finish_sso(sub: "upstream-14", email: "ada@acme.test")

    assert_nil signed_in_actor
    assert_equal 1, within(@tenant) { Actor.count }
  end

  test "a confirmed address still takes up an invitation that is waiting" do
    create_provider(email_domains: "acme.test")
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")
    invited = within(@tenant) { Actor.create!(nickname: "ada", email: "ada@acme.test") }

    finish_sso(sub: "upstream-15", email: "ada@acme.test")

    assert_equal invited.id, signed_in_actor&.id
  end

  test "a state from another browser is refused" do
    create_provider(provisions: true)
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    handoff = begin_sso
    @upstream.announce(
      { "sub" => "upstream-5", "email" => "x@acme.test", "email_verified" => true,
        "nonce" => handoff["nonce"] }
    )

    get "/login/provider/acme/callback", params: { code: "upstream-code", state: "not-the-state" }

    assert_nil signed_in_actor
  end

  test "an id_token minted for another sign-in is refused" do
    create_provider(provisions: true)
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    handoff = begin_sso
    @upstream.announce(
      { "sub" => "upstream-6", "email" => "y@acme.test", "email_verified" => true,
        "nonce" => "a nonce from somewhere else" }
    )

    get "/login/provider/acme/callback", params: { code: "upstream-code", state: handoff["state"] }

    assert_nil signed_in_actor
    assert_equal 1, within(@tenant) { Actor.count }
  end

  test "the handoff carries pkce and a nonce, and redeems with the verifier" do
    create_provider(provisions: true)
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    handoff = begin_sso

    assert_equal "S256", handoff["code_challenge_method"]
    assert handoff["code_challenge"].present?
    assert handoff["nonce"].present?
    assert_includes handoff["scope"].split, "openid"

    finish_sso(sub: "upstream-7", email: "z@acme.test", handoff: handoff)

    sent = @upstream.bodies_for("/o/token").last
    digest = Base64.urlsafe_encode64(
      OpenSSL::Digest::SHA256.digest(sent["code_verifier"].to_s), padding: false
    )

    assert_equal handoff["code_challenge"], digest
  end

  test "a provider that only brokers connections signs nobody in" do
    create_provider(signs_in: false, issuer: nil)

    body = begin_sso

    assert_nil body["redirectTo"]
    assert_nil body["providers"]
    assert_nil signed_in_actor
  end

  test "the sign-in page offers the providers that sign people in" do
    create_provider
    create_provider(key: "quiet", name: "Quiet", signs_in: false, issuer: nil)
    create_actor(@tenant, nickname: "ada", email: "ada@acme.test")

    get "/login"

    assert_response :success
    assert_equal [ { "key" => "acme", "name" => "Acme" } ], auth_data["providers"]
    assert_match "Continue with Acme", response.body
  end

  test "a provider sign-in is one factor, not two" do
    create_provider
    actor = create_actor(@tenant, nickname: "ada", email: "ada@acme.test")
    within(@tenant) { actor.update!(email_verified_at: Time.current) }

    finish_sso(sub: "upstream-8", email: "ada@acme.test")
    prove

    enable_otp(actor)
    within(@tenant) { Session.live.find_each(&:revoke!) }

    reset!
    host! host_for(@tenant)
    finish_sso(sub: "upstream-8", email: "ada@acme.test")

    assert_nil signed_in_actor

    get "/login"

    assert_equal "second-factor", auth_data["prompt"]
  end

  test "an authorize request survives the trip to the provider and back" do
    create_provider(provisions: true, email_domains: "acme.test")
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")
    registration = register(@tenant)

    authorize(client_id: registration["client_id"])

    handoff = begin_sso(rid: current_rid)

    assert handoff["state"].present?

    finish_sso(sub: "upstream-10", email: "roundtrip@acme.test", handoff: handoff)

    follow_redirect! while response.redirect? && URI.parse(response.location).host.to_s.end_with?(".auth.test")

    assert_equal "consent", auth_data["prompt"]
  end

  test "scopes handed to a provisioned account may not be privileged" do
    provider = create_provider(provisions: true)

    within(@tenant) do
      provider.signup_scopes = "openid masks:manage"

      assert_not provider.valid?
      assert_match(/masks:manage/, provider.errors.full_messages.join)
    end
  end

  test "an issuer that answers for somebody else is not trusted" do
    within(@tenant) do
      assert_raises(Provider::Untrusted) { Provider.discover(@upstream.url("/borrowed")) }
    end
  end

  test "discovery reads the endpoints an issuer publishes" do
    within(@tenant) do
      document = Provider.discover(@upstream.url)

      assert_equal @upstream.url("/o/token"), document["token_endpoint"]
      assert_equal @upstream.url("/o/jwks"), document["jwks_uri"]
    end
  end
end
