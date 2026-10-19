module Masks
  module Server
    require "test_helper"

    class SignalJobTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      ENDPOINT = "https://receiver.example.com/events".freeze

      setup do
        @receiver = within do
          Client.new(
            client_id: SecureRandom.uuid, name: "Receiver", grant_types: [ Client::CLIENT_CREDENTIALS ], response_types: [],
            allowed_scopes: Scopes::SIGNALS, approved_at: Time.current
          ).tap { |client| client.issue_secret! }.tap(&:save!)
        end
        @stream = within do
          SignalStream.create!(
            client: @receiver, issuer: "http://#{@tenant.subdomain}.auth.test", endpoint_url: ENDPOINT,
            events_requested: [ Signals::SESSION_REVOKED ], status: SignalStream::ENABLED
          )
        end
      end

      test "a signal the receiver keeps refusing is recorded as undelivered after the last retry and not tried again" do
        stub_request(:post, ENDPOINT).to_return(status: 500)

        perform_enqueued_jobs { within { SignalJob.perform_later(@stream.id, state: "verify-me") } }

        assert_no_enqueued_jobs(only: SignalJob)
        assert within { Event.exists?(action: Event::SIGNAL_UNDELIVERED, client: @receiver) }
        assert within { @stream.reload.last_failure.present? }
      end
    end
  end
end
