module Masks
  module PhoneAdapters
    class TestPhone < Abstract
      class << self
        def verifications
          @verifications ||= {}
        end
      end

      def setup?
        true
      end

      def notify(phone)
        code = SecureRandom.alphanumeric(7)

        self.class.verifications[phone.number] = code

        code
      end

      def verify(phone, code)
        self.class.verifications[phone.number] == code
      end
    end
  end
end
