module Masks
  module Server
    require "test_helper"

    class SharedSignalsTest < ActionDispatch::IntegrationTest
      ENDPOINT = "https://receiver.example.com/events".freeze
      PASSWORD_CHANGE = Signals::CREDENTIAL_CHANGE

      setup do
        host! host_for(@tenant)
        @receiver = receiver
        @actor = create_actor(email: "ada@probe.example.com")
      end

      def receiver(name: "Receiver", scopes: Scopes::SIGNALS)
        within do
          Client.new(
            client_id: SecureRandom.uuid, name: name, grant_types: [ Client::CLIENT_CREDENTIALS ], response_types: [],
            allowed_scopes: scopes, approved_at: Time.current
          ).tap { |client| client.issue_secret! }.tap(&:save!)
        end
      end

      def bearer(client = @receiver)
        token(grant_type: Client::CLIENT_CREDENTIALS, client_id: client.client_id, client_secret: client.secret)["access_token"]
      end

      def ssf(verb, path, body = nil, client: @receiver, **query)
        send(verb, "/ssf/#{path}#{"?#{query.to_query}" if query.any?}",
             params: body&.to_json,
             headers: { "Authorization" => "Bearer #{bearer(client)}", "CONTENT_TYPE" => "application/json" })

        response.body.present? ? JSON.parse(response.body) : nil
      end

      def open_stream(events = [ PASSWORD_CHANGE, Signals::SESSION_REVOKED ], client: @receiver)
        ssf(:post, "streams", { delivery: { method: SignalStream::PUSH, endpoint_url: ENDPOINT, authorization_header: "Bearer inbound" },
                                events_requested: events }, client: client)
      end

      def follow(actor = @actor, client = @receiver)
        within { Consent.record!(actor: actor, client: client, scopes: "openid", audience: []) }
      end

      def delivered
        seen = []
        stub_request(:post, ENDPOINT).to_return { |request| seen << request and { status: 202 } }

        perform_enqueued_jobs { yield }

        seen
      end

      test "the configuration names the endpoints and push delivery" do
        get "/.well-known/ssf-configuration"

        body = JSON.parse(response.body)

        assert_equal origin_for(@tenant), body["issuer"]
        assert_equal [ SignalStream::PUSH ], body["delivery_methods_supported"]
        assert_equal "#{origin_for(@tenant)}/ssf/streams", body["configuration_endpoint"]
      end

      test "a receiver opens a stream and reads it back" do
        created = open_stream

        assert_response :created
        assert_equal @receiver.client_id, created["aud"]
        assert_equal origin_for(@tenant), created["iss"]
        assert_equal [ PASSWORD_CHANGE, Signals::SESSION_REVOKED ].sort, created["events_delivered"].sort
        assert_nil created["delivery"]["authorization_header"]

        assert_equal [ created["stream_id"] ], ssf(:get, "streams").map { |stream| stream["stream_id"] }
        assert_equal created["stream_id"], ssf(:get, "streams", stream_id: created["stream_id"])["stream_id"]
      end

      test "a receiver holds one stream" do
        open_stream
        body = open_stream

        assert_response :conflict
        assert_equal "invalid_request", body["error"]
      end

      test "a token without the signals scope is refused" do
        other = receiver(name: "Other", scopes: "uris:catalog:read")

        ssf(:get, "streams", client: other)

        assert_response :forbidden
      end

      test "a person's token cannot manage a stream" do
        get "/ssf/streams"

        assert_response :unauthorized
      end

      test "an unsupported delivery method or event is refused" do
        body = ssf(:post, "streams", { delivery: { method: "urn:ietf:rfc:8936" }, events_requested: [ PASSWORD_CHANGE ] })

        assert_response :bad_request
        assert_match "push delivery", body["error_description"]

        ssf(:post, "streams", { delivery: { method: SignalStream::PUSH, endpoint_url: ENDPOINT }, events_requested: [ "https://example.com/made-up" ] })

        assert_response :bad_request
      end

      test "a changed password reaches a receiver the person uses, signed by the tenant" do
        open_stream
        follow

        seen = delivered { within { Event.record!(Event::PASSWORD_CHANGED, actor: @actor) } }

        assert_equal 1, seen.size
        assert_equal "application/secevent+jwt", seen.first.headers["Content-Type"]
        assert_equal "Bearer inbound", seen.first.headers["Authorization"]

        header = JWT.decode(seen.first.body, nil, false).last
        claims = claims_in(seen.first.body)

        assert_equal "secevent+jwt", header["typ"]
        assert_equal @receiver.client_id, claims["aud"]
        assert_equal({ "format" => "iss_sub", "iss" => origin_for(@tenant), "sub" => @actor.uuid }, claims["sub_id"])
        assert_equal({ "credential_type" => "password", "change_type" => "update" },
                     claims["events"][PASSWORD_CHANGE].slice("credential_type", "change_type"))
        assert_equal "user", claims["events"][PASSWORD_CHANGE]["initiating_entity"]
      end

      def organized(client = @receiver)
        acme = within { Organization.create!(key: "acme", name: "Acme") }
        keeper = create_actor(nickname: "keeper")

        within do
          acme.memberships.create!(actor: keeper, role: "owner")
          AccessToken.create!(actor: @actor, client: client, organization: acme, scopes: "openid", audience: [],
                              digest: SecureRandom.uuid, expires_at: 1.hour.from_now)
        end

        [ acme, within { acme.memberships.create!(actor: @actor, role: "member") } ]
      end

      test "a role change reaches the apps signed in to that organization as a change to the org claim" do
        open_stream([ Signals::TOKEN_CLAIMS_CHANGE ])
        acme, membership = organized

        seen = delivered { within { Members.assign!(membership, role: "owner", by: nil) } }

        assert_equal 1, seen.size

        change = claims_in(seen.first.body)["events"][Signals::TOKEN_CLAIMS_CHANGE]

        assert_equal({ "id" => acme.uuid, "key" => "acme", "name" => "Acme", "role" => "owner" }, change.dig("claims", "org"))
        assert_equal "system", change["initiating_entity"]
      end

      test "removal from an organization revokes the session of the apps signed in to it" do
        open_stream([ Signals::SESSION_REVOKED ])
        _, membership = organized

        seen = delivered { within { Members.remove!(membership, by: nil) } }

        assert_equal 1, seen.size
        assert claims_in(seen.first.body)["events"].key?(Signals::SESSION_REVOKED)
      end

      test "an app the person uses outside the organization hears nothing of it" do
        open_stream([ Signals::TOKEN_CLAIMS_CHANGE, Signals::SESSION_REVOKED ])
        follow
        _, membership = organized(receiver(name: "Elsewhere"))

        seen = delivered { within { Members.assign!(membership, role: "owner", by: nil) } }

        assert_empty seen
      end

      test "a receiver hears nothing about people who never used it" do
        open_stream

        seen = delivered { within { Event.record!(Event::PASSWORD_CHANGED, actor: @actor) } }

        assert_empty seen
      end

      test "a receiver the person turned away hears nothing more, whatever tokens it once held" do
        open_stream
        follow

        within do
          AccessToken.create!(actor: @actor, client: @receiver, scopes: "openid", audience: [],
                              digest: SecureRandom.uuid, expires_at: 1.hour.from_now, consumed_at: Time.current)
          Consent.live.find_by!(actor: @actor, client: @receiver).revoke!
        end

        seen = delivered { within { Event.record!(Event::PASSWORD_CHANGED, actor: @actor) } }

        assert_empty seen
      end

      test "a receiver whose only token was revoked hears nothing more" do
        open_stream

        within do
          AccessToken.create!(actor: @actor, client: @receiver, scopes: "openid", audience: [],
                              digest: SecureRandom.uuid, expires_at: 1.hour.from_now, consumed_at: Time.current)
        end

        seen = delivered { within { Event.record!(Event::PASSWORD_CHANGED, actor: @actor) } }

        assert_empty seen
      end

      test "a receiver hears only the events it asked for" do
        open_stream([ Signals::SESSION_REVOKED ])
        follow

        seen = delivered { within { Event.record!(Event::PASSWORD_CHANGED, actor: @actor) } }

        assert_empty seen
      end

      test "a receiver that loses the signals scope hears nothing more" do
        open_stream
        follow
        within { @receiver.update!(allowed_scopes: "openid") }

        seen = delivered { within { Event.record!(Event::PASSWORD_CHANGED, actor: @actor) } }

        assert_empty seen
      end

      test "a paused stream holds its events" do
        created = open_stream
        follow

        state = ssf(:post, "status", { stream_id: created["stream_id"], status: SignalStream::PAUSED, reason: "maintenance" })

        assert_equal SignalStream::PAUSED, state["status"]

        seen = delivered { within { Event.record!(Event::PASSWORD_CHANGED, actor: @actor) } }

        assert_empty seen
      end

      test "a pairwise receiver sees the person under its own subject" do
        within { @receiver.update_columns(subject_type: Subjects::PAIRWISE) }
        open_stream
        follow

        seen = delivered { within { Event.record!(Event::PASSWORD_CHANGED, actor: @actor) } }

        sub = claims_in(seen.first.body).dig("sub_id", "sub")

        assert_not_equal @actor.uuid, sub
        assert_equal @actor.id, within { Subjects.locate(sub)&.id }
      end

      test "verification sends the state back" do
        created = open_stream

        seen = delivered { ssf(:post, "verify", { stream_id: created["stream_id"], state: "abc123" }) }

        assert_equal "abc123", claims_in(seen.first.body).dig("events", Signals::VERIFICATION, "state")
      end

      test "a receiver cannot reach another receiver's stream" do
        created = open_stream
        other = receiver(name: "Other")

        ssf(:get, "streams", client: other, stream_id: created["stream_id"])

        assert_response :not_found

        ssf(:delete, "streams", client: other, stream_id: created["stream_id"])

        assert_response :not_found
      end

      test "a receiver updates and removes its stream" do
        created = open_stream

        updated = ssf(:patch, "streams", { stream_id: created["stream_id"], events_requested: [ Signals::ACCOUNT_DISABLED ] })

        assert_equal [ Signals::ACCOUNT_DISABLED ], updated["events_delivered"]
        assert_equal ENDPOINT, updated.dig("delivery", "endpoint_url")

        ssf(:delete, "streams", stream_id: created["stream_id"])

        assert_response :no_content
        assert_empty ssf(:get, "streams")
        assert_equal [ Event::SIGNAL_STREAM_CREATED, Event::SIGNAL_STREAM_UPDATED, Event::SIGNAL_STREAM_DELETED ],
                     within { Event.where(client: @receiver).order(:id).pluck(:action) }
      end

      test "a delivery that keeps failing is recorded" do
        open_stream
        follow
        stub_request(:post, ENDPOINT).to_return(status: 500)

        perform_enqueued_jobs { within { Event.record!(Event::PASSWORD_CHANGED, actor: @actor) } }

        assert within { Event.exists?(action: Event::SIGNAL_UNDELIVERED, client: @receiver) }
      end
    end
  end
end
