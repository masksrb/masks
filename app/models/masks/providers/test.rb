module Masks
  module Providers
    class Test < Abstract
      def setup?
        Rails.env.test?
      end

      def omniauth_args
        []
      end

      def omniauth_strategy
        OmniAuth::Strategies::Developer
      end
    end
  end
end
