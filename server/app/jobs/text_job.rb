class TextJob < ApplicationJob
  queue_as :mailers

  retry_on Adapter::Failed, wait: :polynomially_longer, attempts: 3

  def perform(to, body)
    adapter = Current.tenant&.sms_adapter

    return if adapter.nil?

    adapter.deliver(to: to, body: body)
  end
end
