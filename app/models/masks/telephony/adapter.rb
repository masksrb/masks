module Masks
  module Telephony
    class Adapter
      attr_reader :conf

      def initialize(conf)
        @conf = conf
      end

      def setup?
        false
      end

      def notify
        raise NotImplementedError
      end

      def verify(code)
        raise NotImplementedError
      end
    end
  end
end
