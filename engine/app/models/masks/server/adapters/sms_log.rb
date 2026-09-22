module Masks
  module Server
    module Adapters
      class SmsLog < Sms
        self.label = "Log only (development)"

        def self.deliveries
          @deliveries ||= []
        end

        def deliver(to:, body:)
          self.class.deliveries << { to: to, body: body }
          ::Rails.logger.info("[sms] to #{to}: #{body}")
          true
        end
      end
    end
  end
end
