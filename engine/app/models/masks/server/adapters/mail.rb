module Masks
  module Server
    module Adapters
      class Mail < Adapter
        self.kind = MAIL

        field :from, label: "From address", hint: "Every email masks sends comes from here."

        validate :from_is_an_address

        def from
          self[:from]
        end

        def delivery_method
          raise NotImplementedError
        end

        def deliver_test(to)
          raise Failed, "that is not an email address" unless to.to_s.match?(URI::MailTo::EMAIL_REGEXP)

          AdapterMailer.trial(to, adapter: self).deliver_now
        rescue Net::SMTPError, IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError => error
          raise Failed, error.message
        end

        private

          def from_is_an_address
            errors.add(:base, "From address must be an email address") if
              from.present? && !from.match?(URI::MailTo::EMAIL_REGEXP)
          end
      end
    end
  end
end
