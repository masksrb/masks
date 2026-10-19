module Masks
  module Server
    require "test_helper"

    class TextJobTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        within { Senders::SmsLog.create!(key: "log", name: "Log", primary: true) }
        Senders::SmsLog.deliveries.clear
      end

      def failing_sender
        held = Senders::SmsLog.instance_method(:deliver)
        Senders::SmsLog.define_method(:deliver) { |to:, body:| raise Sender::Failed, "the gateway refused the message" }

        yield
      ensure
        Senders::SmsLog.define_method(:deliver, held)
      end

      test "a text that fails on its last retry is recorded as undelivered and is not tried again" do
        failing_sender do
          perform_enqueued_jobs { within { TextJob.perform_later("+15555550100", "Your code is 123456") } }
        end

        assert_no_enqueued_jobs(only: TextJob)
        assert_empty Senders::SmsLog.deliveries

        event = within { Event.find_by(action: Event::TEXT_UNDELIVERED) }

        assert event
        assert_equal "the gateway refused the message", event.details["said"]
        refute_includes event.details.to_json, "5555550100"
      end

      test "a text the sender takes is delivered once and records nothing" do
        perform_enqueued_jobs { within { TextJob.perform_later("+15555550100", "Your code is 123456") } }

        assert_equal 1, Senders::SmsLog.deliveries.size
        refute within { Event.exists?(action: Event::TEXT_UNDELIVERED) }
      end
    end
  end
end
