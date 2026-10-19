module Masks
  module Server
    class TextJob < ApplicationJob
      queue_as :mailers

      ATTEMPTS = 3

      retry_on Sender::Failed, wait: :polynomially_longer, attempts: ATTEMPTS do |job, error|
        job.gave_up!(error)
      end

      def perform(to, body)
        sender = Current.tenant&.sms_sender

        return if sender.nil?

        sender.deliver(to: to, body: body)
      end

      def gave_up!(error)
        Tenant.switch(held_tenant) do
          Event.record!(Event::TEXT_UNDELIVERED, actor: nil, by: nil, device: nil, ip_address: nil, user_agent: nil,
                                                 said: error.message)
        end
      end
    end
  end
end
