module Masks
  module Server
    class ForwardCode < Token
      def self.lifetime
        2.minutes
      end

      def return_to
        held("return_to")
      end
    end
  end
end
