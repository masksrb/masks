module Masks
  module SessionBag
    class Primitive < Abstract
      def key
        name
      end

      def replace(value)
        self["value"] = value
      end

      def value
        self["value"]
      end
    end
  end
end
