module Masks
  module Server
    class EventStreamJob < ApplicationJob
      queue_as :streams

      retry_on EventStream::Refused, wait: :polynomially_longer, attempts: EventStream::ATTEMPTS do |job, error|
        job.gave_up!(error)
      end

      def perform(stream_id, event_id)
        stream = EventStream.active.find_by(id: stream_id)
        event = Event.includes(:actor, :by, :client).find_by(id: event_id)

        return if stream.nil? || event.nil?

        stream.deliver!(event)
        stream.delivered!
      rescue EventStream::Refused => error
        stream&.failed!(error.message)

        raise
      end

      def gave_up!(error)
        stream_id, event_id = arguments

        Tenant.switch(held_tenant) do
          stream = EventStream.find_by(id: stream_id)
          event = Event.find_by(id: event_id)

          Event.record!(
            Event::STREAM_FAILED,
            actor: nil, by: nil, device: nil, ip_address: nil, user_agent: nil,
            stream: stream&.key, delivering: event&.action, said: error.message
          )
        end
      end
    end
  end
end
