module Masks
  module Server
    require "test_helper"

    class SessionPoliciesTest < ActionDispatch::IntegrationTest
      setup do
        @actor = create_actor(email: "owner@probe.example.com")
        @registration = register
        host! host_for(@tenant)
      end

      def tenant_policy(**attributes)
        within do
          SignInPolicy.create!(key: "tenant", name: "Tenant", **attributes).tap { |held| @tenant.update!(sign_in_policy: held) }
        end
      end

      def client_policy(**attributes)
        within do
          SignInPolicy.create!(key: "client", name: "Client", **attributes).tap do |held|
            Client.find_by!(client_id: @registration["client_id"]).update!(sign_in_policy: held)
          end
        end
      end

      def reaches_the_app?
        authorize(client_id: @registration["client_id"], state: SecureRandom.hex(4))
        consent! if awaiting_consent?

        response.redirect? && code_from.present?
      end

      test "a policy's lifetime decides when a session started under it expires" do
        tenant_policy(session_lifetime: 1.hour.to_i)

        sign_in_as(@actor)

        within { assert_in_delta 1.hour.from_now, Session.sole.expires_at, 5.seconds }
      end

      test "a session with no policy lifetime keeps the default" do
        sign_in_as(@actor)

        within { assert_in_delta Session::LIFETIME.from_now, Session.sole.expires_at, 5.seconds }
      end

      test "a session idle past its timeout ends and is recorded" do
        tenant_policy(session_idle_timeout: 15.minutes.to_i)
        sign_in_as(@actor)

        travel 16.minutes do
          refute reaches_the_app?
          assert awaiting_login?
        end

        within do
          assert Session.sole.revoked_at.present?
          assert_equal "idle", Event.where(action: Event::SESSION_EXPIRED).sole.details["reason"]
        end
      end

      test "a session that keeps being used outlasts its idle timeout" do
        tenant_policy(session_idle_timeout: 15.minutes.to_i)
        sign_in_as(@actor)

        travel(10.minutes) { assert reaches_the_app? }
        travel(20.minutes) { assert reaches_the_app? }
      end

      test "an app whose policy allows a shorter lifetime asks again in an older session" do
        sign_in_as(@actor)
        client_policy(session_lifetime: 1.hour.to_i)

        travel 2.hours do
          authorize(client_id: @registration["client_id"])

          assert awaiting_login?
          assert_equal "first-factor", auth_data["prompt"]
        end
      end

      test "an app whose policy has an idle timeout asks again after a long gap" do
        sign_in_as(@actor)
        client_policy(session_idle_timeout: 15.minutes.to_i)

        travel 30.minutes do
          authorize(client_id: @registration["client_id"])

          assert awaiting_login?
          assert_equal "first-factor", auth_data["prompt"]
        end
      end

      test "an app whose policy has an idle timeout lets a session in use through" do
        sign_in_as(@actor)
        client_policy(session_idle_timeout: 15.minutes.to_i)

        travel(10.minutes) { assert reaches_the_app? }
      end

      test "a refresh token stops working once the bounded session it came from has ended" do
        tenant_policy(session_lifetime: 1.hour.to_i)

        body = access_token_for(actor: @actor, registration: @registration)

        travel 2.hours do
          refreshed = token(grant_type: "refresh_token", refresh_token: body["refresh_token"],
                            client_id: @registration["client_id"], client_secret: @registration["client_secret"])

          assert_equal "invalid_grant", refreshed["error"]
          assert_match "session", refreshed["error_description"]
        end
      end

      test "a refresh token from a session with no policy bounds outlives it" do
        body = access_token_for(actor: @actor, registration: @registration)

        delete "/login"

        refreshed = token(grant_type: "refresh_token", refresh_token: body["refresh_token"],
                          client_id: @registration["client_id"], client_secret: @registration["client_secret"])

        assert refreshed["access_token"].present?, refreshed.inspect
      end

      test "an idle timeout must be shorter than the lifetime, and neither can be absurd" do
        policy = within { SignInPolicy.new(key: "p", name: "P", session_lifetime: 600, session_idle_timeout: 900) }

        refute within { policy.valid? }
        assert policy.errors[:session_idle_timeout].any?

        policy = within { SignInPolicy.new(key: "p", name: "P", session_idle_timeout: 10) }

        refute within { policy.valid? }
      end
    end
  end
end
