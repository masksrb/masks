module Masks
  module Server
    require "test_helper"
    require_relative "../support/upstream"

    class ReceivedSignalsTest < ActionDispatch::IntegrationTest
      include Federated

      REVOKED = "https://schemas.openid.net/secevent/caep/event-type/session-revoked".freeze

      setup do
        @actor = create_actor(@tenant, nickname: "ada")
        @provider = create_provider(receives_signals: true, jwks: { "keys" => [ @upstream.jwk ] }, jwks_fetched_at: Time.current)
        within { Connection.create!(provider: @provider, actor: @actor, subject: "upstream-1", email: "ada@acme.test", connected_at: Time.current) }
      end

      def event(type: REVOKED, subject: { "format" => "iss_sub", "iss" => @upstream.url, "sub" => "upstream-1" },
                aud: origin_for(@tenant), jti: SecureRandom.uuid, typ: "secevent+jwt", key: nil, iss: @upstream.url,
                iat: Time.current.to_i)
        JWT.encode(
          { "iss" => iss, "aud" => aud, "iat" => iat, "jti" => jti,
            "events" => { type => { "subject" => subject } } }.compact,
          key || @upstream.instance_variable_get(:@key), "RS256", kid: "upstream-key", typ: typ
        )
      end

      def deliver(token)
        post "/ssf/events", params: token, headers: { "CONTENT_TYPE" => "application/secevent+jwt" }
        response
      end

      def signed_in?
        within { Session.live.where(actor_id: @actor.id).exists? }
      end

      test "a session revoked at the provider signs the account out everywhere here" do
        sign_in_as(@actor)
        assert signed_in?

        deliver(event)

        assert_response :accepted
        assert_not signed_in?
        within do
          recorded = Event.where(action: Event::SIGNAL_RECEIVED).sole
          assert_equal @actor.id, recorded.actor_id
          assert_equal REVOKED, recorded.details["event"]
        end
      end

      test "an account named by email is found through its connection" do
        sign_in_as(@actor)

        deliver(event(subject: { "format" => "email", "email" => "ada@acme.test" }))

        assert_response :accepted
        assert_not signed_in?
      end

      test "an event type masks does not act on is accepted and changes nothing" do
        sign_in_as(@actor)

        deliver(event(type: "https://schemas.openid.net/secevent/caep/event-type/assurance-level-change"))

        assert_response :accepted
        assert signed_in?
      end

      test "a token signed with another key is refused" do
        sign_in_as(@actor)

        deliver(event(key: OpenSSL::PKey::RSA.generate(2048)))

        assert_response :bad_request
        assert_equal "invalid_key", JSON.parse(response.body)["err"]
        assert signed_in?
      end

      test "a provider that was not set to send signals is refused" do
        within { @provider.update!(receives_signals: false) }

        deliver(event)

        assert_equal "invalid_issuer", JSON.parse(response.body)["err"]
      end

      test "a token for another receiver, of another type, or seen before is refused" do
        assert_equal "invalid_audience", JSON.parse(deliver(event(aud: "https://elsewhere.example.com")).body)["err"]
        assert_equal "invalid_request", JSON.parse(deliver(event(typ: "JWT")).body)["err"]

        held = event
        assert_response :accepted, deliver(held).body
        assert_match "already been received", JSON.parse(deliver(held).body)["description"]
      end

      test "a token with no issue time, one older than the replay memory, or one from the future is refused" do
        assert_match "carries iat", JSON.parse(deliver(event(iat: nil)).body)["description"]

        stale = deliver(event(iat: (ReceivedSignal::MEMORY + 1.hour).ago.to_i))

        assert_match "not issued within", JSON.parse(stale.body)["description"]
        assert_match "not issued within", JSON.parse(deliver(event(iat: 1.hour.from_now.to_i)).body)["description"]
      end

      test "a subject from another issuer matches nobody" do
        sign_in_as(@actor)

        deliver(event(subject: { "format" => "iss_sub", "iss" => "https://other.example.com", "sub" => "upstream-1" }))

        assert_response :accepted
        assert signed_in?
      end
    end
  end
end
