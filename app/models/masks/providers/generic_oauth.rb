module Masks
  module Providers
    class GenericOAuth < Abstract
      include OAuthProvider

      def omniauth_strategy
        OmniAuth::Strategies::OAuth2Generic
      end
    end
  end
end
