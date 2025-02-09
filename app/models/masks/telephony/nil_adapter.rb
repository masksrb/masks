module Masks
  module Telephony
    class NilAdapter < Adapter
      def notify
        false
      end

      def verify(code)
        false
      end
    end
  end
end
