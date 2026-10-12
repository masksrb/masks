require_relative "test_helper"

class DeviceTest < ClientTest
  def session(**options)
    Masks::Client::Session.new(issuer: issuer.url, client_id: "tv", **options)
  end

  def device(**body)
    Masks::Client::Device.new({ "device_code" => "dc", "user_code" => "ABCD-EFGH",
                                "verification_uri" => "#{issuer.url}/device", "expires_in" => 600 }.merge(body.transform_keys(&:to_s)))
  end

  def answers(*bodies)
    held = bodies.dup
    issuer.override("/token", ->(_) { held.size > 1 ? held.shift : held.first })
  end

  def pending
    [ 400, { "error" => "authorization_pending", "error_description" => "nobody has approved this device yet" } ]
  end

  def granted
    { "access_token" => "at", "token_type" => "Bearer", "expires_in" => 60 }
  end

  def test_a_device_authorization_names_the_client_scope_and_every_resource
    issuer.override("/device_authorization", {
      "device_code" => "dc", "user_code" => "ABCD-EFGH", "verification_uri" => "#{issuer.url}/device",
      "verification_uri_complete" => "#{issuer.url}/device?user_code=ABCD-EFGH", "expires_in" => 600, "interval" => 5
    })

    started = session.device_authorization(scope: %w[openid xixo:catalog:read], resource: [ "https://app.test/mcp", "https://app.test/api" ])
    sent = issuer.last("/device_authorization")

    assert_equal [ "dc", "ABCD-EFGH", 5, 600 ], [ started.device_code, started.user_code, started.interval, started.expires_in ]
    assert_equal "#{issuer.url}/device?user_code=ABCD-EFGH", started.verification_uri_complete
    assert_equal({ "client_id" => "tv", "scope" => "openid xixo:catalog:read", "resource" => "https://app.test/api" }, sent[:body])
    refute_includes started.inspect, "dc"
  end

  def test_a_device_authorization_without_a_user_code_is_refused
    issuer.override("/device_authorization", { "device_code" => "dc", "verification_uri" => "#{issuer.url}/device" })

    error = assert_raises(Masks::Client::Rejected) { session.device_authorization }

    assert_match(/user_code/, error.message)
  end

  def test_polling_waits_through_pending_and_answers_the_tokens
    answers(pending, pending, granted)

    tokens = session.await_device(device, pause: 0.01)
    sent = issuer.last("/token")[:body]

    assert_equal "at", tokens.access_token
    assert_equal 3, issuer.count("/token")
    assert_equal [ Masks::Client::Device::GRANT_TYPE, "dc", "tv" ], sent.values_at("grant_type", "device_code", "client_id")
  end

  def test_slow_down_lengthens_the_interval_for_every_poll_after_it
    answers([ 400, { "error" => "slow_down" } ], granted)
    started = Time.now

    session.await_device(device, pause: 0.2)

    assert_operator Time.now - started, :>=, 0.6
  end

  def test_the_interval_the_server_names_is_the_one_waited
    answers(granted)
    started = Time.now

    session.await_device(device(interval: 1), pause: 0.01)

    assert_operator Time.now - started, :>=, 1
  end

  def test_a_denied_device_stops_polling
    answers([ 400, { "error" => "access_denied", "error_description" => "the person turned this device away" } ])

    error = assert_raises(Masks::Client::Rejected) { session.await_device(device, pause: 0.01) }

    assert_equal "access_denied", error.code
    assert_equal 1, issuer.count("/token")
  end

  def test_an_expired_code_stops_polling
    answers([ 400, { "error" => "expired_token", "error_description" => "that device code has expired" } ])

    error = assert_raises(Masks::Client::Rejected) { session.await_device(device, pause: 0.01) }

    assert_equal "expired_token", error.code
  end

  def test_a_code_past_its_expiry_is_not_polled
    error = assert_raises(Masks::Client::Rejected) { session.await_device(device(expires_in: -1), pause: 0.01) }

    assert_equal "expired_token", error.code
    assert_equal 0, issuer.count("/token")
  end

  def test_a_device_held_to_a_key_proves_every_poll
    dpop = Masks::Client::Key.generate
    answers(pending, granted.merge("token_type" => "DPoP"))

    tokens = session(dpop: dpop).await_device(device, pause: 0.01)
    proofs = issuer.received.select { |held| held[:path] == "/token" }.map { |held| held[:headers]["dpop"] }

    assert_predicate tokens, :bound?
    assert_equal 2, proofs.compact.uniq.size
  end
end
