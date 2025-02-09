module Masks
  module SessionBag
    class Check < Abstract
      def key
        name
      end

      def replace(expiry)
        data["checked"] = true

        refresh(expiry)
      end

      def value
        args[:checked] ? instance_exec(&args[:checked]) : checked?
      rescue KeyError
        false
      end

      private

      def checked?
        data["checked"]&.present?
      end
    end
  end
end
