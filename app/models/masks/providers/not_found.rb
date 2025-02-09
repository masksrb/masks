module Masks
  module Providers
    class NotFound < Abstract
      def setup?
        false
      end

      def omniauth_strategy
        nil
      end
    end
  end
end
