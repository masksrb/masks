module Masks
  module Server
    class TextJob < ApplicationJob
      queue_as :mailers

      retry_on Sender::Failed, wait: :polynomially_longer, attempts: 3

      def perform(to, body)
        sender = Current.tenant&.sms_sender

        return if sender.nil?

        sender.deliver(to: to, body: body)
      end
    end
  end
end
