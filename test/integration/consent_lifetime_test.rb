module Masks
  module Server
    require "test_helper"

    class ConsentLifetimeTest < ActionDispatch::IntegrationTest
      setup do
        @actor = create_actor(email: "owner@probe.example.com", name: "Owner")
        @registration = register
        host! host_for(@tenant)
      end

      def client
        within { Client.find_by(client_id: @registration["client_id"]) }
      end

      def asked
        sign_in_as(@actor)
        authorize(client_id: @registration["client_id"], state: SecureRandom.hex(8))
      end

      test "a consent lasts until revoked by default" do
        asked
        consent!

        travel 400.days do
          asked
          assert_not awaiting_consent?
        end
      end

      test "a client's consent lifetime asks the person again once it passes" do
        within { client.update!(consent_lifetime: 30.days.to_i) }
        asked
        consent!

        travel 29.days do
          asked
          assert_not awaiting_consent?
        end

        travel 31.days do
          asked
          assert awaiting_consent?
          assert within { Consent.live.where(actor: @actor).none? }
        end
      end

      test "a lifetime under five minutes or over 400 days is refused" do
        within do
          held = client
          held.consent_lifetime = 60
          assert_not held.valid?
          held.consent_lifetime = 401.days.to_i
          assert_not held.valid?
        end
      end
    end
  end
end
