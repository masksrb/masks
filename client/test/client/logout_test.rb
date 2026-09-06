require_relative "test_helper"

class LogoutTest < Minitest::Test
  EVENT = Masks::Client::Logout::EVENT
  CLIENT_ID = "app-1".freeze

  def setup
    @issuer = FakeIssuer.new
  end

  def teardown
    @issuer.stop
    Masks::Client.registry.clear!
  end

  def token(**overrides)
    claims = {
      "iss" => @issuer.url,
      "aud" => CLIENT_ID,
      "iat" => Time.now.to_i,
      "jti" => SecureRandom.uuid,
      "sub" => "actor-1",
      "sid" => "session-1",
      "events" => { EVENT => {} }
    }.merge(overrides)

    @issuer.sign(claims.compact)
  end

  def verify(value)
    Masks::Client::Logout.verify(value, issuer: @issuer.url, audience: CLIENT_ID)
  end

  def refused(value)
    assert_raises(Masks::Client::InvalidToken) { verify(value) }
  end

  def test_a_token_the_issuer_signed_for_this_client_names_who_signed_out
    logout = verify(token)

    assert_equal "actor-1", logout.subject
    assert_equal "session-1", logout.sid
    assert logout.jti
  end

  def test_a_session_alone_is_enough_to_act_on
    assert_equal "session-1", verify(token("sub" => nil)).sid
  end

  def test_a_subject_alone_is_enough_too
    assert_equal "actor-1", verify(token("sid" => nil)).subject
  end

  def test_a_token_naming_neither_is_refused
    refused token("sub" => nil, "sid" => nil)
  end

  def test_an_id_token_handed_over_in_its_place_is_refused
    refused token("nonce" => "n-1")
  end

  def test_a_token_about_something_else_is_refused
    refused token("events" => { "http://schemas.openid.net/event/other" => {} })
  end

  def test_a_token_with_no_events_at_all_is_refused
    refused token("events" => nil)
  end

  def test_an_events_claim_that_is_not_an_object_is_refused
    refused token("events" => { EVENT => "yes" })
  end

  def test_a_token_for_another_client_is_refused
    refused token("aud" => "app-2")
  end

  def test_a_token_from_another_issuer_is_refused
    other = FakeIssuer.new

    begin
      refused(other.sign({
        "iss" => other.url, "aud" => CLIENT_ID, "iat" => Time.now.to_i,
        "jti" => SecureRandom.uuid, "sub" => "actor-1",
        "events" => { EVENT => {} }
      }))
    ensure
      other.stop
    end
  end

  def test_a_token_nobody_signed_is_refused
    refused(JWT.encode(
      { "iss" => @issuer.url, "aud" => CLIENT_ID, "iat" => Time.now.to_i,
        "jti" => SecureRandom.uuid, "sub" => "actor-1", "events" => { EVENT => {} } },
      nil, "none"
    ))
  end

  def test_a_token_issued_well_ahead_of_now_is_refused
    refused token("iat" => Time.now.to_i + 3600)
  end

  def test_a_session_verifies_a_logout_token_against_its_own_client_id
    session = Masks::Client::Session.new(
      issuer: @issuer.url, client_id: CLIENT_ID, redirect_uri: "https://app.test/callback"
    )

    assert_equal "actor-1", session.logout_token(token).subject
  end
end
