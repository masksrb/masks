require_relative "test_helper"

class HandshakeTest < ClientTest
  APP = "https://app.test".freeze

  def handshake(**overrides)
    Masks::Client::Handshake.new(
      "#{issuer.url}/",
      **{
        name: "uris",
        resource: "#{APP}/mcp",
        redirect_uris: [ "#{APP}/auth/callback" ],
        scope: %w[openid uris:read],
        return_to: "#{APP}/auth/handshake/callback"
      }.merge(overrides)
    )
  end

  def query(**overrides)
    URI.decode_www_form(URI.parse(handshake(**overrides).url(state: "a-state")).query)
       .group_by(&:first)
       .transform_values { |pairs| pairs.map(&:last) }
  end

  def registered(client_id: "client-1", client_secret: "secret-1")
    issuer.override("/register", {
      "client_id" => client_id,
      "client_secret" => client_secret,
      "client_name" => "uris",
      "redirect_uris" => [ "#{APP}/auth/callback" ],
      "scope" => "openid uris:read",
      "registration_access_token" => "registration-token",
      "registration_client_uri" => "#{issuer.url}/register/#{client_id}"
    })
  end

  def returned(**overrides)
    { "initial_access_token" => "one-time", "iss" => issuer.url, "state" => "a-state" }
      .merge(overrides)
  end

  def test_the_endpoint_comes_from_discovery_rather_than_a_path_written_down
    assert handshake.url(state: "x").start_with?("#{issuer.url}/handshake?")
    assert_equal 1, issuer.count("/.well-known/openid-configuration")
  end

  def test_an_issuer_that_advertises_nothing_still_gets_a_url
    issuer.override("/.well-known/openid-configuration",
                    issuer.discovery.except("handshake_endpoint"))

    assert handshake.url(state: "x").start_with?("#{issuer.url}/handshake?")
  end

  def test_an_unreachable_issuer_still_gets_a_url
    away = Masks::Client::Handshake.new(
      "http://127.0.0.1:1",
      name: "uris", resource: "#{APP}/mcp", redirect_uris: [ APP ],
      return_to: "#{APP}/back", scope: %w[openid]
    )

    assert away.url(state: "x").start_with?("http://127.0.0.1:1/handshake?")
  end

  def test_every_value_the_approval_screen_shows_travels_in_the_query
    held = query

    assert_equal [ "uris" ], held["client_name"]
    assert_equal [ "#{APP}/mcp" ], held["resource"]
    assert_equal [ "openid uris:read" ], held["scope"]
    assert_equal [ "#{APP}/auth/handshake/callback" ], held["return_to"]
    assert_equal [ "a-state" ], held["state"]
  end

  def test_redirect_uris_repeat_rather_than_joining
    held = query(redirect_uris: [ "#{APP}/a", "#{APP}/b" ])

    assert_equal [ "#{APP}/a", "#{APP}/b" ], held["redirect_uris"]
  end

  def test_a_scope_string_and_a_scope_list_ask_for_the_same_thing
    assert_equal query(scope: "openid uris:read"), query(scope: %w[openid uris:read])
  end

  def test_starting_mints_the_state_the_caller_has_to_hold
    started = handshake.start

    assert_includes started[:url], "state=#{started[:state]}"
    assert_operator started[:state].length, :>=, 32
    refute_equal handshake.start[:state], handshake.start[:state]
  end

  def test_completing_redeems_the_token_as_a_bearer_and_names_the_client
    registered

    registration = handshake.complete(returned, state: "a-state")

    assert_equal "client-1", registration.client_id
    assert_equal "secret-1", registration.client_secret
    assert_equal "registration-token", registration.access_token

    sent = issuer.last("/register")

    assert_equal "POST", sent[:method]
    assert_equal "Bearer one-time", sent[:headers]["authorization"]
    assert_equal "uris", sent[:body]["client_name"]
    assert_equal [ "#{APP}/auth/callback" ], sent[:body]["redirect_uris"]
    assert_equal "openid uris:read", sent[:body]["scope"]
    assert_includes sent[:body]["grant_types"], "refresh_token"
  end

  def test_a_state_that_does_not_match_this_browser_redeems_nothing
    registered

    error = assert_raises(Masks::Client::Rejected) do
      handshake.complete(returned(state: "forged"), state: "a-state")
    end

    assert_equal "invalid_state", error.code
    assert_equal 0, issuer.count("/register")
  end

  def test_a_browser_holding_no_state_redeems_nothing
    registered

    error = assert_raises(Masks::Client::Rejected) do
      handshake.complete(returned, state: nil)
    end

    assert_equal "invalid_state", error.code
    assert_equal 0, issuer.count("/register")
  end

  def test_an_answer_from_another_issuer_redeems_nothing
    registered

    error = assert_raises(Masks::Client::Rejected) do
      handshake.complete(returned(iss: "https://elsewhere.test"), state: "a-state")
    end

    assert_equal "invalid_issuer", error.code
    assert_equal 0, issuer.count("/register")
  end

  def test_a_refusal_is_carried_through_rather_than_read_as_a_token
    error = assert_raises(Masks::Client::Rejected) do
      handshake.complete(
        { "error" => "access_denied", "error_description" => "the person declined",
          "state" => "a-state" },
        state: "a-state"
      )
    end

    assert_equal "access_denied", error.code
    assert_equal "the person declined", error.description
  end

  def test_a_callback_carrying_no_token_is_refused_before_anything_is_sent
    error = assert_raises(Masks::Client::Rejected) do
      handshake.complete(returned(initial_access_token: nil), state: "a-state")
    end

    assert_equal "invalid_request", error.code
    assert_equal 0, issuer.count("/register")
  end

  def test_a_token_the_issuer_will_not_honour_is_a_refusal_from_the_issuer
    error = assert_raises(Masks::Client::Rejected) do
      handshake.complete(returned, state: "a-state")
    end

    assert_equal "not_found", error.code
  end

  def test_symbol_keys_are_the_same_callback_as_string_keys
    registered

    registration = handshake.complete(
      { initial_access_token: "one-time", iss: issuer.url, state: "a-state" },
      state: "a-state"
    )

    assert_equal "client-1", registration.client_id
  end

  def test_the_registration_it_returns_is_the_one_a_session_is_built_from
    registered

    session = handshake.complete(returned, state: "a-state")
                       .session(redirect_uri: "#{APP}/auth/callback")

    assert_equal "client-1", session.client_id
    assert_equal "secret-1", session.client_secret
    assert_equal issuer.url, session.issuer.url
  end
end
