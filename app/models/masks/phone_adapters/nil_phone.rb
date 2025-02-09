module Masks
  module PhoneAdapters
    class NilPhone < Abstract
      def notify(phone)
        false
      end

      def verify(phone, code)
        false
      end
    end
  end
end
