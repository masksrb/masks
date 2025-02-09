module Masks
  module Providers
    class Github < Abstract
      include OauthProvider

      def omniauth_strategy
        OmniAuth::Strategies::GitHub
      end
    end
  end
end
