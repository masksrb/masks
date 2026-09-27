module Masks
  module Server
    class SignalJob < ApplicationJob
      queue_as :streams

      retry_on SignalStream::Refused, wait: :polynomially_longer, attempts: SignalStream::ATTEMPTS do |job, error|
        job.gave_up!(error)
      end

      def perform(stream_id, event_id: nil, state: nil)
        stream = SignalStream.includes(:client).find_by(id: stream_id)

        return if stream.nil? || stream.status == SignalStream::DISABLED || !stream.receiving?

        if event_id
          event = Event.includes(:actor).find_by(id: event_id)

          return if event&.actor.nil? || stream.status != SignalStream::ENABLED

          stream.deliver!(stream.security_event_token(event))
        else
          stream.deliver!(stream.verification_token(state))
        end
      rescue SignalStream::Refused => error
        stream&.failed!(error.message)

        raise
      end

      def gave_up!(error)
        stream_id, = arguments

        Tenant.switch(held_tenant) do
          stream = SignalStream.find_by(id: stream_id)

          Event.record!(
            Event::SIGNAL_UNDELIVERED,
            actor: nil, by: nil, client: stream&.client, device: nil, ip_address: nil, user_agent: nil,
            said: error.message
          )
        end
      end
    end
  end
end
