module Masks
  module Server
    require "test_helper"

    class EventStreamTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      URL = "https://siem.example.com/hooks/masks".freeze

      setup do
        @actor = create_actor(@tenant, email: "owner@example.com")
      end

      def stream(**attributes)
        within { EventStream.create!(key: "siem", name: "SIEM", url: URL, **attributes) }
      end

      def record(action = Event::ACTOR_UPDATED)
        within { Event.record!(action, actor: @actor, ip_address: "203.0.113.9", user_agent: "curl") }
      end

      test "a stream is created with a secret the receiver can verify with" do
        held = stream

        assert_equal 64, held.secret.length
        assert_empty held.actions
      end

      test "an address that is not https is refused" do
        held = within { EventStream.new(key: "siem", name: "SIEM", url: "ftp://siem.example.com") }

        refute held.valid?
        assert_includes held.errors[:url], "must be an https address"
      end

      test "an address carrying a password is refused" do
        held = within { EventStream.new(key: "siem", name: "SIEM", url: "https://user:pass@siem.example.com") }

        refute held.valid?
      end

      test "an action masks does not record is refused" do
        held = within { EventStream.new(key: "siem", name: "SIEM", url: URL, actions: [ "coffee.brewed" ]) }

        refute held.valid?
        assert_match "coffee.brewed", held.errors[:actions].to_sentence
      end

      test "an event on a stream with no filter is enqueued" do
        stream

        assert_enqueued_with(job: EventStreamJob) { record }
      end

      test "an event the filter leaves out is not enqueued" do
        stream(actions: [ Event::PASSKEY_ADDED ])

        assert_no_enqueued_jobs(only: EventStreamJob) { record }
      end

      test "an archived stream hears nothing" do
        stream(archived_at: Time.current)

        assert_no_enqueued_jobs(only: EventStreamJob) { record }
      end

      test "the event that reports a stream giving up is never streamed" do
        stream

        assert_no_enqueued_jobs(only: EventStreamJob) do
          within { Event.record!(Event::STREAM_FAILED, actor: nil, by: nil, stream: "siem") }
        end
      end

      test "a delivery is signed so the receiver can verify it" do
        held = stream
        event = record
        seen = nil

        stub_request(:post, URL).with { |request| seen = request }.to_return(status: 204)

        within { held.deliver!(event) }

        body = JSON.parse(seen.body)

        assert_equal event.action, body["action"]
        assert_equal @actor.uuid, body["actor"]
        assert_equal "203.0.113.9", body["ip_address"]
        assert_equal event.action, seen.headers["Masks-Event"]
        assert EventStream.verified?(held.secret, seen.headers["Masks-Signature"], seen.body)
      end

      test "a signature over another body, another secret, or an old timestamp does not verify" do
        secret = "s" * 64
        stamp = Time.current.to_i
        header = "t=#{stamp},v1=#{EventStream.sign(secret, stamp, '{}')}"

        assert EventStream.verified?(secret, header, "{}")
        refute EventStream.verified?(secret, header, "{ }")
        refute EventStream.verified?("x" * 64, header, "{}")
        refute EventStream.verified?(secret, header, "{}", now: 10.minutes.from_now)
        refute EventStream.verified?(secret, "garbage", "{}")
      end

      test "a receiver that answers with an error is refused so the delivery is retried" do
        held = stream
        event = record

        stub_request(:post, URL).to_return(status: 500)

        assert_raises(EventStream::Refused) { within { held.deliver!(event) } }
      end

      test "the job keeps what a failing receiver said as the stream's last failure" do
        held = stream
        event = record

        stub_request(:post, URL).to_return(status: 503)

        within { EventStreamJob.perform_now(held.id, event.id) }

        assert_match "503", within { held.reload.last_failure }
      end

      test "a delivery that lands clears the last failure and stamps the time" do
        held = stream
        event = record

        within { held.failed!("earlier trouble") }
        stub_request(:post, URL).to_return(status: 200)

        within { EventStreamJob.perform_now(held.id, event.id) }

        within do
          held.reload

          assert_nil held.last_failure
          assert held.last_delivered_at
        end
      end

      test "giving up records one stream.failed event that names the stream" do
        held = stream
        event = record

        within { EventStreamJob.new(held.id, event.id) }.gave_up!(EventStream::Refused.new("SIEM answered 500"))

        failed = within { Event.where(action: Event::STREAM_FAILED).sole }

        assert_equal "siem", failed.details["stream"]
        assert_equal event.action, failed.details["delivering"]
      end
    end
  end
end
