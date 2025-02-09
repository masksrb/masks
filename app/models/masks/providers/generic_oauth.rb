module Masks
  module Providers
    class GenericOauth < Abstract
      include OauthProvider

      def omniauth_strategy
        OmniAuth::Strategies::OAuth2Generic
      end
    end
  end
end
