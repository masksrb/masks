module Masks
  module Providers
    class GenericOIDC < Abstract
      include OAuthProvider

      def omniauth_strategy
        OmniAuth::Strategies::OpenIDConnect
      end
    end
  end
end
