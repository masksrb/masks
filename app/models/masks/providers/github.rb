module Masks
  module Providers
    class Github < Abstract
      include OAuthProvider

      def omniauth_strategy
        OmniAuth::Strategies::GitHub
      end
    end
  end
end
