module Masks
  module PhoneAdapters
    class Abstract
      attr_reader :install

      def initialize(install)
        @install = install
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
