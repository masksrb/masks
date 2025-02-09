module Masks
  module Providers
    class GenericOpenid < Abstract
      include OauthProvider

      def omniauth_strategy
        OmniAuth::Strategies::OpenIDConnect
      end
    end
  end
end
